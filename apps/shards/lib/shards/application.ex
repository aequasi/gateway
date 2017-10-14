defmodule Shards.Application do
  use Application

  def start(_type, _args) do
    cluster_name = Plumbus.get_env("CITADEL_DOMAIN")
    if cluster_name, do: Citadel.Nodes.join_cluster()
    Citadel.start()

    token         = Plumbus.get_env("TOKEN", nil, :string)
    shards_count  = Plumbus.get_env("SHARDS_COUNT", 1, :integer)
    bucket_id     = Plumbus.get_env("BUCKET_ID", 0, :integer)
    buckets_count = Plumbus.get_env("BUCKETS_COUNT", 1, :integer)
    Shards.start_link(token, shards_count, bucket_id, buckets_count)
  end
end
