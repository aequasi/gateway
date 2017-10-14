defmodule Guilds.Guild.Members do
  use Bitwise

  def new(guild) do
    guild
    |> Map.get(:members, [])
    |> Enum.reduce(Map.put(guild, :members, %{}), &add(&2, &1))
  end

  def add(state, member) do
    member = %{
      user:  member.user,
      roles: member.roles,
      nick:  Map.get(member, :nick)
    }
    members = state.members |> Map.put(member.user.id, member)
    %{state | members: members}
  end

  def update(state, _member_id, member) do
    add(state, member)
  end

  def remove(state, member_id) do
    members = state.members |> Map.delete(member_id)
    %{state | members: members}
  end

  def pop(state, member_id) do
    {member, members} = Map.pop(state.members, member_id)
    {member, %{state | members: members}}
  end

  def permissions(state, member) do
    everyone = Map.get(state.roles, state.id)
    Enum.reduce(member.roles, everyone.permissions, fn role_id, perm ->
      role = Map.get(state.roles, role_id)
      bor(perm, role.permissions)
    end)
  end

end
