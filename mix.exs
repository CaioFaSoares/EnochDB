defmodule Enoch.MixProject do
  use Mix.Project

  def project do
    [
      app: :enoch,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Enoch.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:decimal, "~> 3.2"},
      {:telemetry, "~> 1.0"},
      {:exqlite, "~> 0.42", optional: true},
      {:stream_data, "~> 1.0", only: :test}
    ]
  end
end
