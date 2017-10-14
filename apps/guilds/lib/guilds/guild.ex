defmodule Guilds.Guild do
  use GenServer
  use Bitwise

  alias Guilds.Guild.{Members, Channels, Roles, VoiceStates}

  require Logger

  def start_link(guild_id, joined \\ false) do
    GenServer.start_link(__MODULE__, {guild_id, joined})
  end

  def dispatch(pid, event) do
    send(pid, {:dispatch, event, self()})
  end

  def get(pid, timeout \\ 5_000) do
    GenServer.call(pid, :get, timeout)
  end

  def get_members(pid, timeout \\ 5_000) do
    GenServer.call(pid, :get_members, timeout)
  end

  def get_member(pid, id, timeout \\ 5_000) do
    GenServer.call(pid, {:get_member, id}, timeout)
  end

  def subscribe(guild_id) do
    Citadel.Groups.join(pub_sub_group(guild_id))
  end

  def unsubscribe(guild_id) do
    Citadel.Groups.leave(pub_sub_group(guild_id))
  end

  def voice_state_update(pid, channel_id) do
    send(pid, {:voice_state_update, channel_id})
  end

  def init({guild_id, joined}) do
    Logger.metadata(guild_id: guild_id)
    guild = %{id: guild_id,
              unavailable: true,
              joined: joined}
    {:ok, guild}
  end

  def terminate(_reason, _state), do: :ok

  def handle_call(:start_handoff, from, state) do
    GenServer.reply(from, {:restart, state})
    {:stop, :normal, state}
  end

  def handle_call({:end_handoff, handoff_state}, _state) do
    noreply(handoff_state)
  end

  def handle_call(_msg, _from, %{unavailable: true}=state) do
    reply(:unavailable, state)
  end

  def handle_call({:get_member, id}, _from, state) do
    state
    |> Map.get(:members)
    |> Map.get(id)
    |> reply(state)
  end

  def handle_call(:get_members, _from, state) do
    state
    |> Map.get(:members)
    |> reply(state)
  end

  def handle_call(:get, _from, state) do
    state
    |> Map.drop([:members, :_shard_pid])
    |> reply(state)
  end

  def handle_call(msg, state) do
    Logger.warn "Unhandled cast message #{inspect msg}"
    noreply(state)
  end

  def handle_info(:start, state), do: noreply(state)

  def handle_info({:voice_state_update, channel_id}, state) do
    send(state._shard_pid, {:voice_state_update, state.id, channel_id})
    noreply(state)
  end

  def handle_info({:init, guild}, _state) do
    guild
    |> transform()
    |> noreply()
  end

  def handle_info({:dispatch, event, shard_pid}, state) do
    state = state |> Map.put(:_shard_pid, shard_pid)
    handle_dispatch(event.t, event.d, state)
  end

  def handle_info(msg, state) do
    Logger.warn "Unhandle message #{inspect msg}"
    noreply(state)
  end

  defp handle_dispatch(t, _event, %{unavailable: true}=state) when t != :GUILD_CREATE do
    Logger.warn "Ignoring #{t} event. Unavailable guild."
    noreply(state)
  end

  defp handle_dispatch(:GUILD_CREATE, guild, %{joined: true}=state) do
    guild
    |> transform()
    |> broadcast_event(:GUILD_JOIN)
    |> noreply(:hibernate)
  end

  defp handle_dispatch(:GUILD_CREATE, guild, state) do
    guild
    |> transform()
    |> broadcast_event(:GUILD_UPDATE)
    |> noreply(:hibernate)
  end

  defp handle_dispatch(:GUILD_UPDATE, guild, state) do
    state
    |> Map.merge(guild |> Roles.new())
    |> broadcast_event(:GUILD_UPDATE)
    |> noreply()
  end

  defp handle_dispatch(:GUILD_DELETE, guild, state) do
    is_unavailable = Map.get(guild, :unavailable)
    if is_unavailable do
      state
      |> Map.put(:unavailable, true)
      |> broadcast_event(:GUILD_UPDATE)
      |> noreply()
    else
      state |> broadcast_event(:GUILD_LEAVE)
      {:stop, :normal, state} 
    end
  end

  defp handle_dispatch(:CHANNEL_CREATE, channel, state) do
    state
    |> Channels.add(channel)
    |> broadcast_event(:GUILD_UPDATE)
    |> noreply()
  end

  defp handle_dispatch(:CHANNEL_UPDATE, channel, state) do
    state
    |> Channels.update(channel.id, channel)
    |> broadcast_event(:GUILD_UPDATE)
    |> noreply()
  end

  defp handle_dispatch(:CHANNEL_DELETE, channel, state) do
    state
    |> Channels.remove(channel.id)
    |> broadcast_event(:GUILD_UPDATE)
    |> noreply()
  end

  defp handle_dispatch(:GUILD_ROLE_CREATE, %{role: role}, state) do
    state
    |> Roles.add(role)
    |> broadcast_event(:GUILD_UPDATE)
    |> noreply()
  end

  defp handle_dispatch(:GUILD_ROLE_UPDATE, %{role: role}, state) do
    state
    |> Roles.update(role.id, role)
    |> broadcast_event(:GUILD_UPDATE)
    |> noreply()
  end

  defp handle_dispatch(:GUILD_ROLE_DELETE, %{role_id: role_id}, state) do
    state
    |> Roles.remove(role_id)
    |> broadcast_event(:GUILD_UPDATE)
    |> noreply()
  end

  defp handle_dispatch(:GUILD_MEMBER_ADD, member, state) do
    state
    |> Members.add(member)
    |> broadcast_event(:GUILD_MEMBER_JOIN, member.user.id)
    |> noreply()
  end

  defp handle_dispatch(:GUILD_MEMBER_REMOVE, %{user: user}, state) do
    {member, state} = Members.pop(state, user.id)
    state
    |> broadcast_event(:GUILD_MEMBER_LEAVE, member)
    |> noreply()
  end

  defp handle_dispatch(:GUILD_MEMBER_UPDATE, member, state) do
    state
    |> Members.update(member.user.id, member)
    |> broadcast_event(:GUILD_MEMBER_UPDATE, member.user.id)
    |> noreply()
  end

  defp handle_dispatch(:GUILD_MEMBERS_CHUNK, %{members: members}, state) do
    members_ids = Enum.map(members, &(&1.user.id))

    members
    |> Enum.reduce(state, &Members.update(&2, &1.user.id, &1))
    |> broadcast_event(:GUILD_MEMBERS_UPDATE, members_ids)
    |> noreply()
  end

  defp handle_dispatch(:VOICE_STATE_UPDATE, d, state) do
    state
    |> VoiceStates.update(d.user_id, d)
    |> noreply()
  end

  defp handle_dispatch(:VOICE_SERVER_UPDATE, d, state) do
    state
    |> broadcast_event(:VOICE_SERVER_UPDATE, d)
    |> noreply()
  end

  defp handle_dispatch(:MESSAGE_CREATE, d, state) do
    state
    |> broadcast_event(:MESSAGE_CREATE, d)
    |> noreply()
  end

  defp handle_dispatch(_, _, state), do: noreply(state)

  defp broadcast_event(state, t) when t in [:GUILD_JOIN, :GUILD_UPDATE, :GUILD_LEAVE] do
    state
    |> Map.drop([:members, :voice_states, :_shard_pid])
    |> do_broadcast_event(t, state)
  end

  defp broadcast_event(state, t, member_id) when t in [:GUILD_MEMBER_UDPATE, :GUILD_MEMBER_JOIN] do
    state.members
    |> Map.get(member_id)
    |> do_broadcast_event(t, state)
  end

  defp broadcast_event(state, :GUILD_MEMBERS_UPDATE, members_ids) do
    state.members
    |> Map.take(members_ids)
    |> Map.values()
    |> do_broadcast_event(:GUILD_MEMBERS_UPDATE, state)
  end

  defp broadcast_event(state, :GUILD_MEMBER_LEAVE, member) do
    do_broadcast_event(member, :GUILD_MEMBER_LEAVE, state)
  end

  defp broadcast_event(state, :VOICE_SERVER_UPDATE, d) do
    do_broadcast_event(d, :VOICE_SERVER_UPDATE, state)
  end

  defp broadcast_event(state, :MESSAGE_CREATE, d) do
    member_id = d.author.id

    message     = d
    member      = Map.get(state.members, member_id)

    if member do
      voice_state = Map.get(state.voice_states, member_id)
      guild_perms = Members.permissions(state, member)
      is_owner    = member_id == state.owner_id

      d = %{
        message: message,
        member:  member,
        voice_state: voice_state,
        is_owner: is_owner,
        guild_permissions: guild_perms
      }

      content = d.message.content
      if String.starts_with?(content, "!") do
        [command | rest] = String.split(content, " ")
        text = Enum.join(rest, " ")
        state
        |> broadcast_event(:COMMAND_EXECUTE, command, text, d)
      end

      do_broadcast_event(d, :MESSAGE_CREATE, state)

    else
      state
    end
  end

  defp broadcast_event(state, :COMMAND_EXECUTE, command, text, message_create_payload) do
    d = 
      message_create_payload
      |> Map.put(:command, command)
      |> Map.put(:text, text)

    do_broadcast_event(d, :COMMAND_EXECUTE, state)
  end

  defp broadcast_event(state, _t, _d) do
    state
  end

  defp do_broadcast_event(d, t, state) do
    # PUB/SUB
    msg     = {:guild, state.id, t, d}
    members = Citadel.Groups.members(pub_sub_group(state.id))
    for pid <- members do
      send(pid, msg)
    end

    # Pushing event to the broker
    broker_push(t, d, state)

    state
  end

  @guild_fields [:id, :name, :icon, :owner_id, :roles, :large, :unavailable, :voice_states, :members, :channels]
  def transform(guild) do
    guild
    |> Map.take(@guild_fields)
    |> Channels.new()
    |> Roles.new()
    |> Members.new()
    |> VoiceStates.new()
  end

  defp noreply(state), do: {:noreply, state}

  defp noreply(state, arg), do: {:noreply, state, arg}

  defp reply(msg, state), do: {:reply, msg, state}

  defp pub_sub_group(guild_id), do: {:guild_pub_sub, guild_id}

  defp broker_push(t, d, state) do
    payload =
      %{
        t:  t,
        d:  d,
        g:  state.id,
        ts: :os.system_time(:millisecond)
      }

    channel = "gateway.event.#{t}"
    data    = Poison.encode!(payload)

    RedixStage.cmd(["PUBLISH", channel, data])
  end
end
