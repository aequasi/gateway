defmodule Guilds.Guild.Roles do
  def new(guild) do
    guild
    |> Map.get(:roles, [])
    |> Enum.reduce(Map.put(guild, :roles, %{}), &add(&2, &1))
  end

  def add(state, role) do
    roles = state.roles |> Map.put(role.id, role)
    %{state | roles: roles}
  end

  def update(state, _role_id, new_role) do
    add(state, new_role)
  end

  def remove(state, role_id) do
    roles = state.roles |> Map.delete(role_id)
    %{state | roles: roles}
  end

end
