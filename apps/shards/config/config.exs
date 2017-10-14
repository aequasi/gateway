use Mix.Config

config :vmstats,
  sink: Shards


config :logger,
  level: :info,
  truncate: :infinity
