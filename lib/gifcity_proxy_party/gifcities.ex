defmodule GifcityProxyParty.Gifcities do
  alias GifcityProxyParty.Cache
  alias GifcityProxyPartyWeb.Endpoint
  @salt "gifcities-image-v1"
  @api "https://gifcities.archive.org/api/v1/gifsearch"

  def search(query) when is_binary(query) do
    query = String.trim(query)

    if byte_size(query) in 1..200 do
      Cache.fetch({:search, query}, config(:search_ttl_ms), fn ->
        url = @api <> "?" <> URI.encode_query(%{q: query, seed: "760.1918446952851"})

        with {:ok, body} <- client().get(url, 5 * 1024 * 1024),
             {:ok, rows} when is_list(rows) <- Jason.decode(body) do
          {:ok, rows |> Enum.take(20) |> Enum.flat_map(&result/1)}
        else
          _ -> {:error, :upstream}
        end
      end)
    else
      {:error, :invalid_query}
    end
  end

  def search(_), do: {:error, :invalid_query}

  def image(token) when is_binary(token) and byte_size(token) <= 4096 do
    # Non-expiring signatures keep posted chat URLs usable after cache eviction/restarts.
    with {:ok, capture} <- Phoenix.Token.verify(Endpoint, @salt, token, max_age: :infinity),
         true <- valid_capture?(capture) do
      Cache.fetch({:image, capture}, config(:image_ttl_ms), fn ->
        [timestamp, original] = String.split(capture, "/", parts: 2)
        url = "https://web.archive.org/web/" <> timestamp <> "id_/" <> original

        with {:ok, body} <- client().get(url, 5 * 1024 * 1024),
             true <- gif?(body) do
          {:ok, body}
        else
          _ -> {:error, :upstream}
        end
      end)
    else
      _ -> {:error, :not_found}
    end
  end

  def image(_), do: {:error, :not_found}

  defp result(%{"gif" => capture} = row) do
    if valid_capture?(capture) do
      id = :crypto.hash(:sha256, capture) |> Base.encode16(case: :lower)
      # Fixed signing time makes the image URL deterministic across searches.
      token = Phoenix.Token.sign(Endpoint, @salt, capture, signed_at: 0)
      url = Endpoint.url() <> "/images/" <> token <> ".gif"
      title = if is_binary(row["url_text"]), do: String.slice(row["url_text"], 0, 200), else: ""

      [
        %{
          id: id,
          type: "gif",
          slug: id,
          title: title,
          url: url,
          preview_url: url,
          images: %{original: %{url: url}, fixed_width: %{url: url}}
        }
      ]
    else
      []
    end
  end

  defp result(_), do: []

  defp valid_capture?(capture) when is_binary(capture) and byte_size(capture) <= 2048 do
    Regex.match?(~r/\A[0-9]{14}\/https?:\/\/[^\s\x00-\x1f]+\z/, capture)
  end

  defp valid_capture?(_), do: false
  defp gif?(<<header::binary-size(6), _::binary>>), do: header in ["GIF87a", "GIF89a"]
  defp gif?(_), do: false
  defp client, do: config(:http_client)
  defp config(key), do: Application.fetch_env!(:gifcity_proxy_party, key)
end
