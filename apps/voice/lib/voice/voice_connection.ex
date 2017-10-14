defmodule Voice.VoiceConnection do
  use GenServer

  alias Guilds.Guild

  require Logger

  # WS OP codes

  @opcode_identify            0
  @opcode_select_protocol     1
  @opcode_ready               2
  @opcode_heartbeat           3
  @opcode_session_description 4
  @opcode_speaking            5
  @opcode_heartbeat_ack       6
  @opcode_resume              7
  @opcode_hello               8
  @opcode_resumed             9
  @opcode_client_connect      12
  @opcode_client_disconnect   13

  def start_link(guild_id, channel_id, user_id) do
    GenServer.start_link(__MODULE__, {guild_id, channel_id, user_id})
  end

  def init({guild_id, channel_id, user_id}) do
    Logger.metadata([guild_id: guild_id])
    state = 
      guild_id
      |> initial_state(user_id)
      |> Map.put(:channel_id, channel_id)
      |> get_session_info()
      |> websocket_create()
      |> start_session()
    {:ok, state} 
  end

  def play(pid, url), do: GenServer.call(pid, {:play, url})
  
  def stop(pid), do: GenServer.call(pid, :stop)

  def move(pid, channel_id), do: GenServer.call(pid, {:move, channel_id})

  def leave(pid), do: GenServer.call(pid, :leave)

  def handle_call({:move, channel_id}, from, state) do
    Logger.info "[MOVE] Moving to vc #{channel_id}"

    channel_id =
      case Guilds.voice_state_update(state.guild_id, channel_id) do
        nil -> state.channel_id
        _   -> channel_id
      end

    reply(%{state | channel_id: channel_id}, :ok)
  end

  def handle_call(:leave, from, state) do
    Logger.info "[LEAVE] Leaving guild #{state.guild_id} voice"

    state
    |> websocket_close(1001)
    |> destroy_ffmpeg_port()
    |> Map.get(:guild_id)
    |> Guilds.voice_state_update(nil)

    GenServer.reply(from, :ok)

    {:stop, :normal, ""}
  end

  def handle_call({:play, url}, _from, state) do
    Logger.info "[PLAYING] #{url}"

    state =
      state
      |> destroy_ffmpeg_port()
      |> make_ffmpeg_port(url)

    state
    |> websocket_message(@opcode_speaking, true)
    |> websocket_send(state)
    |> reply(:ok)
  end

  def handle_call(:stop, _from, state) do
    Logger.info "[STOP] Stopping current audio"

    state =
      state
      |> destroy_ffmpeg_port()

    state
    |> websocket_message(@opcode_speaking, false)
    |> websocket_send(state)
    |> reply(:ok)
  end

  def handle_call(msg, _from, state) do
    Logger.warn "Unhandled call message #{inspect msg}"
    noreply(state)
  end

  def handle_info(:heartbeat, %{heartbeat_ack: false}=state) do
    Logger.warn "[NO_HEARTBEAT_ACK]"
    state
    |> websocket_close(1001)
    |> websocket_create()
    |> start_session()
    |> noreply()
  end

  def handle_info(:heartbeat, state) do
    nonce = :os.system_time(:seconds) 
    Logger.info "[HEARTBEAT] #{nonce}"
    state
    |> websocket_message(@opcode_heartbeat, nonce)
    |> websocket_send(state)
    |> schedule_heartbeat()
    |> Map.put(:heartbeat_ack, false)
    |> noreply()
  end

  def handle_info({:websocket, pid, frame}, %{ws_pid: ws_pid}=state) when ws_pid != pid do
    noreply(state)
  end

  def handle_info({:websocket, pid, frame}, %{ws_pid: ws_pid}=state) do
    frame |> handle_websocket_frame(state)
  end

  def handle_info({:DOWN, _, _, pid, reason}, %{ws_pid: ws_pid}=state) when pid == ws_pid do
    Logger.warn "[WS_DOWN] #{inspect(reason)}"
    state
    |> websocket_close(1001)
    |> websocket_create()
    |> noreply()
  end

  def handle_info({:udp, sock, _ip, _port, data}, %{ffmpeg_socket: ffmpeg_socket}=state) when sock==ffmpeg_socket do
    state
    |> transform_rtp_packet(data)
    |> discord_voice_send(state)
    |> noreply()
  end

  def handle_info(_msg, state) do
    noreply(state)
  end

  # Websocket callbacks
   
  defp handle_websocket_frame(:connected, state) do
    Logger.info "[WS_CONNECTED] #{state.ws_url}"
    noreply(state)
  end

  defp handle_websocket_frame({:close, {_, code, msg}}, state) do
    Logger.info "[WS_CLOSED] code: #{code} \"#{msg}\""
    handle_websocket_close(code, state)
  end

  defp handle_websocket_frame({:data, payload}, state) do
    payload = atom_map(payload)
    case payload do
      %{op: op} ->
        handle_incoming_message(op, payload, state)
      payload ->
        # Dealing with:
        #
        # "Unlike the other payloads,
        # Opcode 8 Hello does not have an opcode or a
        # data field denoted by d"
        
        payload = %{op: @opcode_hello, d: payload}
        handle_incoming_message(@opcode_hello, payload, state)
    end
  end

  defp handle_websocket_frame(frame, state) do
    Logger.warn "Unhandled websocket frame #{inspect(frame)}"
    noreply(state)
  end

  defp handle_websocket_close(code, state) when code in [4004, 4006, 4009, 4011] do
    {:stop, {:ws_close, code}, %{}}
  end

  defp handle_websocket_close(_code, state) do
    state
    |> websocket_close(1001)
    |> websocket_create()
    |> start_session()
    |> noreply()
  end

  # INC messages handlers
  
  defp handle_incoming_message(@opcode_hello, %{d: d}, state) do
    heartbeat_interval = round(d.heartbeat_interval * 0.75) # C.F voice heartbeat bug

    Logger.info "[HELLO] heartbeat_interval: #{heartbeat_interval}ms"

    state
    |> Map.put(:heartbeat_interval, heartbeat_interval) 
    |> schedule_heartbeat() # Start heartbeating
    |> start_session() # Start or resume session
    |> noreply()
  end

  defp handle_incoming_message(@opcode_heartbeat_ack, %{d: nonce}, state) do
    Logger.info "[HEARTBEAT_ACK] #{nonce}"
    state
    |> Map.put(:heartbeat_ack, true)
    |> noreply()
  end

  defp handle_incoming_message(@opcode_ready, %{d: d}, state) do
    Logger.info "[READY] ssrc #{d.ssrc} / port #{d.port}"

    state = 
      state
      |> Map.put(:authenticated, true)
      |> Map.put(:ssrc, d.ssrc)
      |> Map.put(:port, d.port)
      |> make_discord_socket()
      |> make_ffmpeg_socket()
      |> discover_ip()

    state
    |> websocket_message(@opcode_select_protocol)
    |> websocket_send(state)
    |> noreply()
  end

  defp handle_incoming_message(@opcode_resumed, _, state) do
    Logger.info "[RESUMED] ssrc #{state.ssrc} / port #{state.port}"
    noreply(state)
  end

  defp handle_incoming_message(@opcode_session_description, %{d: d}, state) do
    Logger.info "[SESSION_DESCRIPTION] Got secret_key"
    pid = self()
    spawn( fn -> play(pid, "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3") end)
    state
    |> Map.put(:secret_key, d.secret_key |> :erlang.list_to_binary())
    |> noreply()
  end

  defp handle_incoming_message(@opcode_speaking, %{d: d}, state) do
    ssrc_map = Map.put(state.ssrc_map, d.ssrc, d.user_id)
    state
    |> Map.put(:ssrc_map, ssrc_map)
    |> noreply()
  end

  defp handle_incoming_message(@opcode_client_connect, %{d: d}, state) do
    ssrc_map = Map.put(state.ssrc_map, d.audio_ssrc, d.user_id)
    state
    |> Map.put(:ssrc_map, ssrc_map)
    |> noreply()
  end

  defp handle_incoming_message(@opcode_client_disconnect, %{d: d}, state) do
    ssrc_map =
      state.ssrc_map
      |> Enum.filter(fn {_ssrc, user_id} -> user_id != d.user_id end)
      |> Map.new()
    state
    |> Map.put(:ssrc_map, ssrc_map)
    |> noreply()
  end

  defp handle_incoming_message(op, p, state) do
    Logger.warn "Unhandled incoming message #{inspect p}"
    state
    |> noreply()
  end

  defp get_session_info(state, timeout \\ 10_000) do
    # guild pid
    pid = Guilds.guild_lookup(state.guild_id)
    # Subscribe to guild events
    Guild.subscribe(state.guild_id)
    # Send voice state update
    Guild.voice_state_update(pid, nil)
    Guild.voice_state_update(pid, state.channel_id)
    # Wait for voice server update
    resp =
      receive do
        {:guild_event, _gid, :VOICE_SERVER_UPDATE, d} ->
          d
      after
        timeout -> :timeout
      end
    Guild.unsubscribe(state.guild_id)

    token      = resp.token
    endpoint   = String.replace(resp.endpoint, ":80", "")
    ws_url     = "wss://#{endpoint}/?v=3"
    {:ok, ip}  = endpoint |> to_charlist() |> :inet.getaddr(:inet)
    session_id =
      state.guild_id
      |> Guilds.get_guild()
      |> Map.get(:voice_states)
      |> Map.get(state.user_id)
      |> Map.get(:session_id)

    state
    |> Map.put(:session_id, session_id)
    |> Map.put(:token, token)
    |> Map.put(:endpoint, endpoint)
    |> Map.put(:ip, ip)
    |> Map.put(:ws_url, ws_url)
  end

  defp initial_state(guild_id, user_id) do
    %{
      # voice conn info
      guild_id:           guild_id,
      user_id:            user_id,
      authenticated:      false,
      token:              nil,
      secret_key:         nil,
      # voice udp
      endpoint:           nil,
      discord_socket:     nil,
      ip:                 nil,
      port:               nil,
      my_ip:              nil,
      my_port:            nil,
      # rtp
      ssrc:               nil,
      ssrc_map:           %{},
      # websocket
      ws_url:             nil,
      ws_pid:             nil,
      heartbeat:          nil,
      heartbeat_interval: nil,
      heartbeat_ack:      true,
      # ffmeg
      ffmpeg_port:        nil,
      ffmpeg_socket:      nil
    }
  end

  # WEBSOCKET stuff

  defp websocket_create(state) do
    {:ok, pid} = Websocket.start(state.ws_url, :json)
    Process.monitor(pid)
    %{state | ws_pid: pid}
  end

  defp websocket_close(%{ws_pid: ws_pid}=state, reason \\ "1001") do
    Websocket.close(ws_pid, reason)
    state
    |> Map.put(:ws_pid, nil)
    |> Map.put(:authenticated, false)
    |> unschedule_heartbeat()
  end

  defp websocket_send(payload, %{ws_pid: nil}=state) do
    Logger.warn "Cannot send websocket payload #{inspect payload}, no ws_pid"
    state
  end

  defp websocket_send(payload, %{ws_pid: ws_pid}=state) do
    payload = Poison.encode!(payload)
    Websocket.send(ws_pid, {:text, payload})
    state
  end

  defp websocket_message(state, @opcode_identify) do
    %{
      "op" => @opcode_identify,
      "d"  => %{
        "server_id"  => state.guild_id,
        "user_id"    => state.user_id,
        "session_id" => state.session_id,
        "token"      => state.token
      }
    }
  end

  defp websocket_message(state, @opcode_resume) do
    %{
      "op" => @opcode_resume,
      "d"  => %{
        "server_id"  => state.guild_id,
        "session_id" => state.session_id,
        "token"      => state.token
      }
    }
  end

  defp websocket_message(state, @opcode_select_protocol) do
    %{
      "op" => @opcode_select_protocol,
      "d"  => %{
        "protocol" => "udp",
        "data"     => %{
          "address" => state.my_ip,
          "port"    => state.my_port,
          "mode"    => "xsalsa20_poly1305"
        }
      }
    }
  end

  defp websocket_message(state, @opcode_speaking, speaking?) do
    %{
      "op" => @opcode_speaking,
      "d"  => %{
        "speaking" => speaking?,
        "delay"    => 0,
        "ssrc"     => state.ssrc
      }
    }
  end

  defp websocket_message(state, @opcode_heartbeat, nonce) do
    %{
      "op" => @opcode_heartbeat,
      "d"  => nonce,
    }
  end

  defp start_session(%{secret_key: nil}=state) do
    state
    |> websocket_message(@opcode_identify)
    |> websocket_send(state)
  end

  defp start_session(state) do
    state
    |> websocket_message(@opcode_resume)
    |> websocket_send(state)
  end

  defp schedule_heartbeat(state) do
    pid  = self()
    task =
      Task.async(fn ->
        Process.sleep(state.heartbeat_interval)
        send(pid, :heartbeat)
      end)
    %{state | heartbeat: task}
  end

  defp unschedule_heartbeat(state) do
    if state.heartbeat, do: Task.shutdown(state.heartbeat)
    %{state | heartbeat_ack: true, heartbeat: nil}
  end

  # DISCORD UDP

  defp make_discord_socket(state) do
    Logger.info "[DISCORD_UDP] Opening discord udp socket"

    opts          = [:binary, active: true]
    {:ok, socket} = :gen_udp.open(0, opts)

    state
    |> Map.put(:discord_socket, socket)
  end

  defp discover_ip(state) do
    # IP/PORT DISCOVERY
    # forming the packet
    frame = << state.ssrc :: size(560) >>
    # sendinng packet
    discord_voice_send(frame, state)
    resp =
      receive do
        {:udp, _, _, _, data} -> data
      after
        5_000 -> :timeout
      end
    # decoding recv packet for ip:port
    << _       :: size(32),
       my_ip   :: bitstring-size(112),
       _       :: size(400),
       my_port :: size(16) >> = resp

    Logger.info "[IP_DISCOVERY] Self ip/port discovery: #{my_ip}:#{my_port}"

    state
    |> Map.put(:my_ip, my_ip)
    |> Map.put(:my_port, my_port)
  end

  defp parse_string(byte, n) do
   case byte do
     <<str :: binary-size(n), 0,  rest :: binary>> ->
       {str, rest}
     byte -> parse_string(byte, n + 1)
   end
  end

  defp discord_voice_send(frame, state) do
    :gen_udp.send(state.discord_socket, state.ip, state.port, frame)
    state
  end

  # RTP

  defp transform_rtp_packet(state, packet) do
    << _t::size(8), _v::size(8), seq::size(16), ts::size(32), _ssrc::size(32), audio::binary >> = packet

    header = << 128::size(8), 120::size(8), seq::size(16), ts::size(32), state.ssrc::size(32) >>
    nonce  = (header <> << 0::size(96) >>)

    encrypted_audio = Kcl.secretbox(audio, nonce, state.secret_key)

    header <> encrypted_audio
  end

  # FFMPEG 

  defp make_ffmpeg_socket(state) do
    Logger.info "[FFMPEG_UDP] Opening ffmpeg udp socket"
    opts          = [:binary, active: true]
    {:ok, socket} = :gen_udp.open(0, opts)
    state
    |> Map.put(:ffmpeg_socket, socket)
  end
  
  defp make_ffmpeg_port(state, url) do
    {:ok, rtp_port} = :inet.port(state.ffmpeg_socket)
    cmd      = "ffmpeg -reconnect 1 -re -reconnect_streamed 1 -reconnect_delay_max 2 -i \"#{url}\" -vn -c:a libopus -ar 48000 -frame_duration 60 -loglevel error -ssrc 1 -f rtp rtp://127.0.0.1:#{rtp_port}"

    ffmpeg_port = Port.open({:spawn, cmd}, [:binary])
    %{state | ffmpeg_port: ffmpeg_port}
  end

  defp destroy_ffmpeg_port(state) do
    case :erlang.port_info(state.ffmpeg_port, :os_pid) do
      {:os_pid, os_pid} ->
        System.cmd("kill", ["#{os_pid}"])
        Port.close(state.ffmpeg_port)
      _ -> nil
    end

    %{state | ffmpeg_port: nil}
  end

  # Misc

  defp noreply(state), do: {:noreply, state}

  defp reply(state, msg), do: {:reply, msg, state}

  defp atom_map(term) when is_map(term), do: for {key, value} <- term, into: %{}, do: {:"#{key}", atom_map(value)}
  defp atom_map(term) when is_list(term), do: Enum.map(term, &atom_map/1)
  defp atom_map(term), do: term

end
