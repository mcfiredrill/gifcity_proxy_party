defmodule GifcityProxyPartyWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :gifcity_proxy_party
  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug GifcityProxyPartyWeb.CORS
  plug Plug.Head
  plug :fetch_query_params
  plug GifcityProxyPartyWeb.Router
end
