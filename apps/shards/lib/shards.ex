defmodule Shards do
  alias Shards.Shard

  require Logger
  @acc ["vmstats.proc_count", "vmstats.gc.count", 
"vmstats.proc_limit", "vmstats.messages_in_queues", "vmstats.run_queue"] 
  def collect(_t, k, v) do
    if false do
      if to_string(k) in @acc do
        Logger.info "#{k} -> #{v}"
      end
    end
  end

  def start_link(token, shards_count \\ 1, bucket_id \\ 0, buckets_count \\ 1) do
    {:ok, sup} = Citadel.Supervisor.start_link(__MODULE__)
    init_shards(token, shards_count, bucket_id, buckets_count)
    {:ok, sup}
  end

  def init_shards(token, shards_count, bucket_id, buckets_count) do
    shards_per_bucket = div(shards_count, buckets_count)
    from              = bucket_id * shards_per_bucket
    to                = (bucket_id + 1) * shards_per_bucket - 1

    for shard_id <- from..to do
      start_shard(token, {shard_id, shards_count})
    end
  end

  def start_shard(token, shard) do
    Citadel.Supervisor.start_child(__MODULE__,
                                   Shard,
                                   [token, shard],
                                   id: shard)
  end

  def shard_lookup(shard_id, shards_count) do
    Citadel.Supervisor.lookup(__MODULE__, {shard_id, shards_count})
  end

  def members do
    Citadel.Supervisor.members(__MODULE__)
  end

  def after_child_start(%{pid: pid}) do
    send(pid, :start)
  end
end
