defmodule Guilds.Guild.Channels do
  def new(guild) do
    guild
    |> Map.get(:channels, [])
    |> Enum.reduce(Map.put(guild, :channels, %{}), &add(&2, &1))
  end

  def add(state, channel) do
    channels = state.channels |> Map.put(channel.id, channel)
    %{state | channels: channels}
  end

  def update(state, _channel_id, new_channel) do
    add(state, new_channel)
  end

  def remove(state, channel_id) do
    channels = state.channels |> Map.delete(channel_id)
    %{state | channels: channels}
  end
end
