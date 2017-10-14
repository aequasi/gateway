defmodule Voice.Mixfile do
  use Mix.Project

  def project do
    [app: :voice,
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

  def application do
    [applications: [:citadel, :websocket, :guilds],
     extra_applications: [:logger],
     mod: {Voice.Application, []}]
  end

  defp deps do
    [{:citadel, git: "ssh://github.com/mee6/citadel.git"},
     {:poison, "~> 3.1"},
     {:kcl, "~> 0.6.3"},
     {:websocket, in_umbrella: true}]
  end
end
