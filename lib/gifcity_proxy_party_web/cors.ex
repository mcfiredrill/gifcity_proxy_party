defmodule GifcityProxyPartyWeb.CORS do
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _) do
    conn = put_resp_header(conn, "vary", "origin")
    origin = List.first(get_req_header(conn, "origin"))

    if origin in Application.fetch_env!(:gifcity_proxy_party, :cors_origins) do
      conn =
        conn
        |> put_resp_header("access-control-allow-origin", origin)
        |> put_resp_header("access-control-allow-methods", "GET, HEAD, OPTIONS")
        |> put_resp_header("access-control-allow-headers", "accept, content-type")

      if conn.method == "OPTIONS", do: conn |> send_resp(204, "") |> halt(), else: conn
    else
      conn
    end
  end
end
