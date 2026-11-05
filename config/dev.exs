import Config

config :gifcity_proxy_party, GifcityProxyPartyWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  debug_errors: true

config :gifcity_proxy_party, :cors_origins, [
  "https://datafruits.fm",
  "https://www.datafruits.fm",
  "http://localhost:4200"
]
