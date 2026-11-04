defmodule GifcityProxyPartyWeb.Router do
  use Phoenix.Router

  scope "/", GifcityProxyPartyWeb do
    get "/health", ProxyController, :health
    get "/search", ProxyController, :search
    get "/images/:filename", ProxyController, :image
  end
end
