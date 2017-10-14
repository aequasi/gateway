defmodule Guilds do
  alias Guilds.Guild

  @pub_sub_group :guilds_pub_sub

  def start_link do
    Citadel.Supervisor.start_link(__MODULE__)
  end

  def start_guild(guild_id, joined \\ false) do
    Citadel.Supervisor.start_child(__MODULE__,
                                   Guilds.Guild,
                                   [guild_id, joined],
                                   id: guild_id)
  end

  def guild_lookup(guild_id) do
    Citadel.Supervisor.lookup(__MODULE__, guild_id)
  end

  def get_guild(guild_id) do
    case guild_lookup(guild_id) do
      nil -> nil
      pid -> Guilds.Guild.get(pid)
    end
  end

  def get_guild_members(guild_id) do
    case guild_lookup(guild_id) do
      nil -> nil
      pid -> Guilds.Guild.get_members(pid)
    end
  end

  def get_guild_member(guild_id, member_id) do
    case guild_lookup(guild_id) do
      nil -> nil
      pid -> Guilds.Guild.get_member(pid, member_id)
    end
  end

  def voice_state_update(guild_id, channel_id) do
    case guild_lookup(guild_id) do
      nil -> nil
      pid -> Guilds.Guild.voice_state_update(pid, channel_id)
    end
  end

  def members do
    Citadel.Supervisor.members(__MODULE__)
  end

  def subscribe do
    Citadel.Groups.join(@pub_sub_group)
  end

  def subscribe(guild_id) do
    Guild.subscribe(guild_id)
  end

  def after_child_start(%{spec: {id, _}, pid: pid}) do
    for pid <- Citadel.Groups.members(@pub_sub_group) do
      send(pid, {:guilds, :GUILD_SPAWN, {id, pid}})
    end
  end
end
