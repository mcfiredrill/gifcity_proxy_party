defmodule GifcityProxyPartyWeb.ProxyController do
  use Phoenix.Controller, formats: [:json]
  alias GifcityProxyParty.Gifcities

  def health(conn, _), do: json(conn, %{status: "ok"})

  def search(conn, params) do
    case Gifcities.search(params["q"]) do
      {:ok, results} ->
        json(conn, %{data: results, pagination: %{count: length(results), offset: 0}})

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def image(conn, %{"filename" => filename}) do
    token =
      if String.ends_with?(filename, ".gif"), do: String.trim_trailing(filename, ".gif"), else: ""

    case Gifcities.image(token) do
      {:ok, body} ->
        conn
        |> put_resp_content_type("image/gif", nil)
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> send_resp(200, body)

      {:error, reason} ->
        error(conn, reason)
    end
  end

  defp error(conn, reason) do
    {status, message} =
      case reason do
        :invalid_query -> {400, "q must be a string between 1 and 200 bytes"}
        :not_found -> {404, "GIF not found"}
        :busy -> {503, "Proxy is busy; try again shortly"}
        :timeout -> {504, "GifCities request timed out"}
        _ -> {502, "GifCities is unavailable"}
      end

    conn
    |> put_status(status)
    |> put_resp_header("cache-control", "no-store")
    |> json(%{error: message})
  end
end
