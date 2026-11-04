import Config

if System.get_env("PHX_SERVER") in ["true", "1"] do
  config :gifcity_proxy_party, GifcityProxyPartyWeb.Endpoint, server: true
end

if origins = System.get_env("CORS_ORIGINS") do
  config :gifcity_proxy_party,
         :cors_origins,
         String.split(origins, ",", trim: true) |> Enum.map(&String.trim/1)
end

if config_env() == :prod do
  secret = System.fetch_env!("SECRET_KEY_BASE")
  host = System.fetch_env!("PHX_HOST")

  config :gifcity_proxy_party, GifcityProxyPartyWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4000"))],
    secret_key_base: secret
end
