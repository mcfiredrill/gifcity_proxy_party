defmodule GifcityProxyParty.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: GifcityProxyParty.PubSub},
      {Finch, name: GifcityProxyParty.Finch},
      {Task.Supervisor, name: GifcityProxyParty.Tasks},
      GifcityProxyParty.Cache,
      GifcityProxyPartyWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: GifcityProxyParty.Supervisor)
  end

  def config_change(changed, _new, removed) do
    GifcityProxyPartyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
