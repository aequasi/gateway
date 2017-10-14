defmodule Guilds.Guild.VoiceStates do
  def new(guild) do
    guild
    |> Map.get(:voice_states, [])
    |> Enum.reduce(Map.put(guild, :voice_states, %{}), &add(&2, &1))
  end

  def add(state, voice_state) do
    voice_state =
      voice_state
      |> Map.take([:channel_id, :user_id, :session_id, :deaf, :mute, :self_deaf, :self_mute, :supress])
    voice_states = state.voice_states |> Map.put(voice_state.user_id, voice_state)
    %{state | voice_states: voice_states}
  end

  def update(state, _user_id, voice_state) do
    add(state, voice_state)
  end

  def remove(state, user_id) do
    voice_states = state.voice_states |> Map.delete(user_id)
    %{state | voice_states: voice_states}
  end
end
