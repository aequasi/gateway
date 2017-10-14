defmodule Shards.Shard do
  use GenServer
  use Bitwise

  require Logger

  alias Guilds.Guild

  @ws_url          "wss://gateway.discord.gg/?v=6&encoding=etf&compress=zlib-stream"
  @large_threshold 250
  @compress        false

  # Gateway opcodes

  @opcode_dispatch              0
  @opcode_heartbeat             1
  @opcode_identify              2
  @opcode_status_update         3
  @opcode_voice_state_update    4
  @opcode_voice_server_ping     5
  @opcode_resume                6
  @opcode_reconnect             7
  @opcode_request_guild_members 8
  @opcode_invalid_session       9
  @opcode_hello                 10
  @opcode_heartbeat_ack         11

  def start_link(token, shard \\ {0, 1}) do
    GenServer.start_link(__MODULE__, [token, shard]) 
  end

  # GenServer Callbacks
  
  def init([token, shard]) do
    state = initial_state(token, shard)

    {shard_id, shard_num} = shard
    Logger.metadata(shard: "shard-#{shard_id}-#{shard_num}")

    {:ok, state}
  end

  def terminate(_reason, _state), do: :ok

  def handle_call(:start_handoff, from, state) do
    state = state |> websocket_close()
    GenServer.reply(from, {:handoff, state})
    {:stop, :normal, %{}}
  end

  def handle_call({:end_handoff, handoff_state}, from, _state) do
    GenServer.reply(from, :ok)
    handoff_state
    |> start_session()
    |> noreply()
  end

  def handle_info({:voice_state_update, guild_id, channel_id}, %{authenticated: true}=state) do
    state
    |> websocket_message(guild_id, channel_id, @opcode_voice_state_update)
    |> websocket_send(state)
    |> noreply()
  end

  def handle_info({:websocket, pid, _frame}, %{ws_pid: ws_pid}=state) when ws_pid != pid do
    noreply(state)
  end

  def handle_info({:websocket, _pid, frame}, state) do
    handle_websocket_frame(frame, state)
  end

  def handle_info(:heartbeat, %{heartbeat_ack: false}=state) do
    Logger.warn "[NO_HEARTBEAT_ACK]"
    state
    |> websocket_close(1001)
    |> websocket_create()
    |> noreply()
  end

  def handle_info(:heartbeat, state) do
    state
    |> websocket_message(@opcode_heartbeat)
    |> websocket_send(state)
    |> schedule_heartbeat()
    |> Map.put(:heartbeat_ack, false)
    |> noreply()
  end

  def handle_info({:DOWN, _, _, pid, reason}, %{ws_pid: ws_pid}=state) when pid == ws_pid do
    Logger.info "[WS_DOWN] #{inspect(reason)}"
    state
    |> websocket_close(1001)
    |> websocket_create()
    |> noreply()
  end

  def handle_info({:DOWN, _, _, pid, :normal}, state) do
    guilds =
      state.guilds
      |> Enum.filter(fn {_gid, gpid} -> gpid != pid end)
      |> Map.new()
    noreply(%{state | guilds: guilds})
  end

  def handle_info(:start, state) do
    state
    |> websocket_create()
    |> noreply()
  end

  def handle_info({:ignore_shard, shard}, state) do
    state
    |> ignore_shard(shard)
    |> noreply()
  end

  def handle_info(_, state), do: noreply(state)

  # Websocket Callbacks 
  
  defp handle_websocket_frame(:connected, state) do
    Logger.info "[WS_CONNECTED] #{@ws_url}"
    noreply(state)
  end

  defp handle_websocket_frame({:close, code}, state) do
    Logger.info "[WS_CLOSED] #{inspect(code)}"
    state
    |> websocket_close(1001)
    |> websocket_create()
    |> noreply()
  end

  defp handle_websocket_frame({:data, %{op: op}=payload}, state) do
    handle_incoming_message(op, payload, state)
  end

  defp handle_websocket_frame(frame, state) do
    Logger.warn "Unhandled websocket frame #{inspect(frame)}"
    noreply(state)
  end

  # Incoming Messages Handlers

  defp handle_incoming_message(@opcode_hello, %{d: d}, state) do
    Logger.info "[HELLO] _trace: #{inspect d._trace}, heartbeat_interval: #{d.heartbeat_interval}ms"

    state
    |> Map.put(:heartbeat_interval, d.heartbeat_interval)
    |> schedule_heartbeat() # Start heartbeating
    |> start_session() # Start or resume session
    |> noreply()
  end

  defp handle_incoming_message(@opcode_invalid_session, _, %{session_id: nil}=state) do
    Logger.warn "[INVALID_SESSION] Identify rate limit, retrying..."

    state
    |> websocket_close()
    |> websocket_create()
    |> noreply()
  end

  defp handle_incoming_message(@opcode_invalid_session, _, state) do
    Logger.warn "[INVALID_SESSION] Session got invalidated"
    state
    |> websocket_close()
    |> initial_state()
    |> websocket_create()
    |> noreply()
  end

  defp handle_incoming_message(@opcode_reconnect, _, state) do
    Logger.warn "[RECONNECT] Gateway asked for reconnect"
    state
    |> websocket_close()
    |> websocket_create()
    |> noreply()
  end

  defp handle_incoming_message(@opcode_heartbeat, _, state) do
    state
    |> websocket_message(@opcode_heartbeat)
    |> websocket_send(state)
    |> Map.put(:heartbeat_ack, true)
    |> noreply()
  end
  
  defp handle_incoming_message(@opcode_heartbeat_ack, _, state) do
    state
    |> Map.put(:heartbeat_ack, true)
    |> noreply()
  end

  defp handle_incoming_message(@opcode_dispatch, event, state) do
    %{s: s, d: d, t: t} = event |> sanitize_event()
    {:noreply, state} = handle_dispatch(t, d, state)
    state
    |> Map.put(:seq, s)
    |> noreply()
  end

  defp handle_incoming_message(opcode, _payload, state) do
    Logger.warn "Unhandled opcode #{opcode}"
    noreply(state)
  end

  # Dispatch Events Handlers
  
  defp handle_dispatch(t, d, %{authenticated: false}=state) when not t in [:READY, :RESUMED]  do
    state
    |> Map.put(:events_buffer, [{t, d} | state.events_buffer])
    |> noreply()
  end

  defp handle_dispatch(:READY, d, state) do
    Logger.info "[READY] Got #{length(d.guilds)} guilds"

    for {_, shard} <- Shards.members() do
      send(shard, {:ignore_shard, state.shard})
    end

    guilds = 
      d.guilds
      |> Enum.filter(fn g ->
        not guild_ignored?(g.id, state.ignored_shards)
      end)
      |> Map.new(fn guild ->
        pid =
          case Guilds.guild_lookup(guild.id) do
            nil ->
              {:ok, pid} = Guilds.start_guild(guild.id)
              Process.monitor(pid)
              pid
            pid -> pid
          end
        {guild.id, pid}
      end)

    state
    |> Map.put(:guilds, guilds)
    |> Map.put(:session_id, d.session_id)
    |> Map.put(:_trace, d._trace)
    |> Map.put(:authenticated, true)
    |> noreply()
  end

  defp handle_dispatch(:RESUMED, d, state) do
    buffer_size = length(state.events_buffer)

    state =
      state
      |> Map.put(:events_buffer, Enum.reverse(state.events_buffer))
      |> replay_dispatch_events()

    Logger.info "[RESUMED] Replayed #{buffer_size} events. _trace: #{d._trace}"

    state
    |> Map.put(:authenticated, true)
    |> Map.put(:_trace, d._trace)
    |> noreply()
  end

  defp handle_dispatch(:GUILD_CREATE, guild, %{guilds: guilds}=state) do
    if guild_ignored?(guild.id, state.ignored_shards) do
      noreply(state)
    else
      guilds
      |> Map.get(guild.id)
      |> handle_guild_create(guild, state)
      |> noreply()
    end
  end

  defp handle_dispatch(:CHANNEL_CREATE, channel, state) do
    guild_id        = Map.get(channel, :guild_id)
    channels_guilds =
      state.channels_guilds
      |> Map.put(channel.id, guild_id)

    state = %{state | channels_guilds: channels_guilds}

    do_dispatch(:CHANNEL_CREATE, channel, guild_id, state)
  end

  defp handle_dispatch(:MESSAGE_CREATE, message, state)  do
    guild_id  = Map.get(state.channels_guilds, message.channel_id)
    do_dispatch(:MESSAGE_CREATE, message, guild_id, state)
  end

  defp handle_dispatch(:GUILD_MEMBERS_CHUNK, d, state) do
    do_dispatch(:GUILD_MEMBERS_CHUNK, d, state)
  end

  defp handle_dispatch(:GUILD_MEMBER_ADD, member, state) do
    do_dispatch(:GUILD_MEMBER_ADD, member, state)
  end

  defp handle_dispatch(:USER_UPDATE, _user, state) do
    noreply(state)
  end

  defp handle_dispatch(t, _, state) when t in [:TYPING_START, :PRESENCE_UPDATE] do
    # Ignoring events
    noreply(state)
  end

  defp handle_dispatch(t, d, state) do
    do_dispatch(t, d, state)
  end

  defp do_dispatch(t, d, state) do
    guild_id  = Map.get(d, :guild_id, Map.get(d, :id))
    do_dispatch(t, d, guild_id, state)
  end

  defp do_dispatch(t, d, guild_id, state) do
    pid       = Map.get(state.guilds, guild_id)
    if pid, do: Guild.dispatch(pid, %{t: t, d: d})
    noreply(state)
  end

  # Internals
  
  defp initial_state(%{token: token, shard: shard}), do: initial_state(token, shard)

  defp initial_state(token, shard) do
    %{
      token:              token,
      shard:              shard,
      session_id:         nil,
      seq:                0,
      ws_pid:             nil,
      heartbeat:          nil,
      heartbeat_interval: nil,
      heartbeat_ack:      true,
      authenticated:      false,
      guilds:             %{},
      channels_guilds:    %{},
      events_buffer:      [],
      ignored_shards:     [],
      _trace:             nil
    }
  end

  defp start_session(%{session_id: nil}=state) do
    state
    |> websocket_message(@opcode_identify)
    |> websocket_send(state)
  end

  defp start_session(state) do
    state
    |> websocket_message(@opcode_resume)
    |> websocket_send(state)
  end

  defp ignore_shard(state, shard) do
    %{state | ignored_shards: [shard | state.ignored_shards]}
  end

  defp guild_ignored?(guild_id, [shard | rest]) do
    {sid, scount} = shard
    if rem(guild_id >>> 22, scount) == sid do
      true
    else
      guild_ignored?(guild_id, rest)
    end
  end
  defp guild_ignored?(_guild_id, []), do: false

  defp websocket_message(state, @opcode_identify) do
    %{
      "op" => @opcode_identify,
      "d"  => %{
        "token"           => state.token,
        "compress"        => @compress,
        "large_threshold" => @large_threshold,
        "shard"           => state.shard,
        "properties"      => %{
          "$referring_domain" => "",
          "$referer"          => "",
          "$device"           => "mee6",
          "$browser"          => "mee6",
          "$os"               => "linux",
        }
      }
    }
  end

  defp websocket_message(state, @opcode_heartbeat) do
    %{
      "op" => @opcode_heartbeat,
      "d"  => state.seq
    }
  end

  defp websocket_message(state, guild_id, channel_id, @opcode_voice_state_update) do
    %{
      "op" => @opcode_voice_state_update,
      "d"  => %{
        "guild_id"   => guild_id,
        "channel_id" => channel_id,
        "self_deaf"  => false,
        "self_mute"  => false
      }
    }
  end

  defp websocket_message(state, @opcode_resume) do
    %{
      "op" => @opcode_resume,
      "d"  => %{
        "token"      => state.token,
        "session_id" => state.session_id,
        "seq"        => state.seq
      }
    }
  end

  defp websocket_message(state, guild_id, @opcode_request_guild_members) do
    %{
      "op" => @opcode_request_guild_members,
      "d"  => %{
        "guild_id" => guild_id,
        "query"    => "",
        "limit"    => 0
      }
    }
  end

  defp websocket_send(payload, %{ws_pid: nil}=state) do
    Logger.warn "Cannot send websocket payload #{inspect payload}, no ws_pid"
    state
  end

  defp websocket_send(payload, %{ws_pid: ws_pid}=state) do
    payload = :erlang.term_to_binary(payload)
    Websocket.send_binary(ws_pid, payload)
    state
  end

  defp websocket_create(state) do
    opts = [format: :etf, zlib_stream: true]
    {:ok, pid} = Websocket.start(@ws_url, opts)
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

  defp replay_dispatch_events(state) do
    events_buffer = state.events_buffer
    state         = %{state | events_buffer: [], authenticated: true}
    replay_dispatch_events(events_buffer, state)
  end

  defp replay_dispatch_events([], state), do: %{state | authenticated: false}

  defp replay_dispatch_events([{t, d} | events], state) do
    {:noreply, state} = handle_dispatch(t, d, state)
    replay_dispatch_events(events, state)
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

  defp noreply(state), do: {:noreply, state}

  defp reply(msg, state), do: {:reply, msg, state}

  defp handle_guild_create(nil, guild, %{guilds: guilds}=state) do
    guilds =
      case Guilds.guild_lookup(guild.id) do
        nil ->
          {:ok, pid} = Guilds.start_guild(guild.id, true)
          Process.monitor(pid)
          Map.put(guilds, guild.id, pid)
        pid -> guilds
      end

    state = %{state | guilds: guilds}

    handle_guild_create(Map.get(guilds, guild.id), guild, state)
  end

  defp handle_guild_create(guild_pid, guild, state) do
    Guild.dispatch(guild_pid, %{t: :GUILD_CREATE, d: guild})

    if guild.large do
      state
      |> websocket_message(guild.id, @opcode_request_guild_members)
      |> websocket_send(state)
    end

    channels_guilds =
      guild.channels
      |> Enum.map(fn c -> {c.id, guild.id} end)
      |> Map.new()
      |> Map.merge(state.channels_guilds)

    state
    |> Map.put(:channels_guilds, channels_guilds)
  end

  defp sanitize_event(%{t: t}=event) when not t in [:READY, :PRESENCE_UPDATE, :GUILD_MEMBERS_CHUNK, :GUILD_CREATE] do
    atom_map(event)
  end
  defp sanitize_event(event), do: event

  defp atom_map(term) when is_map(term), do: for {key, value} <- term, into: %{}, do: {:"#{key}", atom_map(value)}
  defp atom_map(term) when is_list(term), do: Enum.map(term, &atom_map/1)
  defp atom_map(term), do: term
end

