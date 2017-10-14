defmodule Voice do
  alias Voice.VoiceConnection

  def start_link do
    Citadel.Supervisor.start_link(__MODULE__)
  end

  def start_voice_connection(guild_id, channel_id, user_id) do
    Citadel.Supervisor.start_child(__MODULE__,
                                   VoiceConnection,
                                   [guild_id, channel_id, user_id],
                                   id: guild_id)
  end

  def voice_connection_lookup(guild_id) do
    Citadel.Supervisor.lookup(__MODULE__, guild_id)
  end

  def members do
    Citadel.Supervisor.members(__MODULE__)
  end

  def join(guild_id, channel_id, user_id) do
    case voice_connection_lookup(guild_id) do
      nil -> start_voice_connection(guild_id, channel_id, user_id)
      pid ->
        VoiceConnection.move(pid, channel_id)
        {:ok, pid}
    end
  end

  def play(guild_id, url) do
    case voice_connection_lookup(guild_id) do
      nil -> nil
      pid -> VoiceConnection.play(pid, url)
    end
  end

  def stop(guild_id) do
    case voice_connection_lookup(guild_id) do
      nil -> nil
      pid -> VoiceConnection.stop(pid)
    end
  end

  def leave(guild_id) do
    case voice_connection_lookup(guild_id) do
      nil -> Guilds.voice_state_update(guild_id, nil)
      pid -> VoiceConnection.leave(pid)
    end
  end
end
