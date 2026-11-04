import Config

config :gifcity_proxy_party,
  http_client: GifcityProxyParty.HTTP,
  search_ttl_ms: 3_600_000,
  image_ttl_ms: 86_400_000,
  cors_origins: ["https://datafruits.fm", "https://www.datafruits.fm"]

config :gifcity_proxy_party, GifcityProxyPartyWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [formats: [json: GifcityProxyPartyWeb.ErrorJSON], layout: false],
  pubsub_server: GifcityProxyParty.PubSub,
  secret_key_base: String.duplicate("development-only-", 4)

config :phoenix, :json_library, Jason
config :logger, :console, format: "$time $metadata[$level] $message\n"
import_config "#{config_env()}.exs"
