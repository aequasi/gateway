defmodule Guilds.Mixfile do
  use Mix.Project

  def project do
    [app: :guilds,
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
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger],
     mod: {Guilds.Application, []}]
  end

  defp deps do
    [{:redix_stage, github: "mee6/redix_stage"},
     {:poison, "~> 3.1"},
     {:citadel, git: "ssh://github.com/mee6/citadel.git"}]
  end
end
