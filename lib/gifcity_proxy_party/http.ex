defmodule GifcityProxyParty.HTTP do
  @moduledoc "Bounded streaming HTTP downloads. Redirects are deliberately not followed."
  def get(url, max_bytes) do
    request =
      Finch.build(:get, url, [
        {"user-agent", "GifcityProxyParty/0.1 (Datafruits chat)"},
        {"accept-encoding", "identity"}
      ])

    initial = %{status: nil, body: [], size: 0, error: nil}

    case Finch.stream_while(
           request,
           GifcityProxyParty.Finch,
           initial,
           fn
             {:status, status}, acc ->
               {:cont, %{acc | status: status}}

             {:data, data}, acc ->
               if acc.size + byte_size(data) > max_bytes do
                 {:halt, %{acc | error: :too_large, body: []}}
               else
                 {:cont, %{acc | size: acc.size + byte_size(data), body: [data | acc.body]}}
               end

             _, acc ->
               {:cont, acc}
           end,
           receive_timeout: 8_000,
           pool_timeout: 2_000
         ) do
      {:ok, %{error: nil, status: 200, body: body}} ->
        {:ok, body |> Enum.reverse() |> IO.iodata_to_binary()}

      {:ok, %{error: error}} when not is_nil(error) ->
        {:error, error}

      {:ok, _} ->
        {:error, :upstream}

      {:error, _} ->
        {:error, :upstream}
    end
  end
end
