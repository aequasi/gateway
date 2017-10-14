defmodule Shards.Mixfile do
  use Mix.Project

  def project do
    [app: :shards,
     version: "0.1.0",
     build_path: "../../_build",
     config_path: "../../config/config.exs",
     deps_path: "../../deps",
     lockfile: "../../mix.lock",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [#applications: [:citadel, :websocket],
     extra_applications: [:logger],
     mod: {Shards.Application, []}]
  end

  defp deps do
    [{:citadel, git: "ssh://github.com/mee6/citadel.git"},
     {:guilds, in_umbrella: true},
     {:recon, "~> 2.3"},
     {:redix_stage, github: "mee6/redix_stage"},
     {:vmstats, "~> 2.2"},
     {:voice, in_umbrella: true},
     {:ezlib, github: "silviucpp/ezlib", app: false},
     {:websocket, in_umbrella: true}]
  end
end
