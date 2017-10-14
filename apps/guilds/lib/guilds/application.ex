defmodule Guilds.Application do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    cluster_name = Plumbus.get_env("CITADEL_DOMAIN")
    if cluster_name, do: Citadel.Nodes.join_cluster()
    Citadel.start()

    children = [
      worker(Guilds, [])
    ]

    opts = [strategy: :one_for_one, name: Guilds.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
