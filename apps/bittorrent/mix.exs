defmodule Bittorrent.MixProject do
  use Mix.Project

  def project do
    [
      app: :bittorrent,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Bittorrent.Application, nil}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bento, "~> 0.9"},
      {:castore, "~> 0.1.0"},
      {:tesla, "~> 1.3.0"},
      {:hackney, "~> 1.15.2"}
    ]
  end

  defp escript do
    [main_module: Bittorrent.CLI]
  end
end
