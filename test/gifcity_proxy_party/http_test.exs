defmodule GifcityProxyParty.HTTPTest do
  use ExUnit.Case, async: true
  @moduletag :network
  alias GifcityProxyParty.HTTP

  defmodule Upstream do
    import Plug.Conn
    def init(opts), do: opts

    def call(conn, _) do
      case conn.request_path do
        "/ok" ->
          send_resp(conn, 200, "GIF89a-data")

        "/large" ->
          conn = send_chunked(conn, 200)
          {:ok, conn} = chunk(conn, "12345")
          {:ok, conn} = chunk(conn, "67890")
          conn

        "/redirect" ->
          conn |> put_resp_header("location", "http://127.0.0.1:1/private") |> send_resp(302, "")

        "/error" ->
          send_resp(conn, 429, "slow down")
      end
    end
  end

  setup do
    server = start_supervised!({Bandit, plug: Upstream, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    %{base: "http://127.0.0.1:#{port}"}
  end

  test "streams successful responses and stops oversized downloads", %{base: base} do
    assert {:ok, "GIF89a-data"} = HTTP.get(base <> "/ok", 100)
    assert {:error, :too_large} = HTTP.get(base <> "/large", 7)
  end

  test "does not follow redirects or accept upstream error pages", %{base: base} do
    assert {:error, :upstream} = HTTP.get(base <> "/redirect", 100)
    assert {:error, :upstream} = HTTP.get(base <> "/error", 100)
  end
end
