import Config

config :gifcity_proxy_party, GifcityProxyPartyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false

config :gifcity_proxy_party, :http_client, GifcityProxyParty.FakeHTTP
config :logger, level: :warning
