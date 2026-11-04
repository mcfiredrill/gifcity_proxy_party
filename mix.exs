defmodule GifcityProxyParty.MixProject do
  use Mix.Project

  def project do
    [
      app: :gifcity_proxy_party,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: [
        {:phoenix, "~> 1.8.1"},
        {:bandit, "~> 1.8.0"},
        {:plug, "~> 1.18.0", override: true},
        {:jason, "~> 1.4"},
        {:finch, "~> 0.20.0"}
      ]
    ]
  end

  def application,
    do: [mod: {GifcityProxyParty.Application, []}, extra_applications: [:logger, :runtime_tools]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
