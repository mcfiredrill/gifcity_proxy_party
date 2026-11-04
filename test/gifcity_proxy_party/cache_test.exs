defmodule GifcityProxyParty.CacheTest do
  use ExUnit.Case, async: true
  alias GifcityProxyParty.Cache

  test "concurrent requests share a fetch while unrelated keys can complete" do
    cache = start_supervised!({Cache, name: nil})
    parent = self()

    fetch = fn ->
      send(parent, {:started, self()})

      receive do
        :finish -> {:ok, "gif"}
      end
    end

    first = Task.async(fn -> Cache.fetch(:same, 1000, fetch, cache) end)
    assert_receive {:started, worker}
    second = Task.async(fn -> Cache.fetch(:same, 1000, fetch, cache) end)
    assert {:ok, "other"} = Cache.fetch(:other, 1000, fn -> {:ok, "other"} end, cache)
    send(worker, :finish)
    assert Task.await(first) == {:ok, "gif"}
    assert Task.await(second) == {:ok, "gif"}
    refute_receive {:started, _}
  end

  test "expiry, capacity, byte bounds and failed fetches allow refetching" do
    cache = start_supervised!({Cache, name: nil, max_entries: 1, max_bytes: 100})
    assert {:ok, 1} = Cache.fetch(:a, 0, fn -> {:ok, 1} end, cache)
    assert {:ok, 2} = Cache.fetch(:a, 1000, fn -> {:ok, 2} end, cache)
    assert {:ok, 3} = Cache.fetch(:b, 2000, fn -> {:ok, 3} end, cache)
    assert {:ok, 4} = Cache.fetch(:a, 3000, fn -> {:ok, 4} end, cache)
    assert {:error, :upstream} = Cache.fetch(:error, 1000, fn -> {:error, :upstream} end, cache)
    assert {:ok, 5} = Cache.fetch(:error, 1000, fn -> {:ok, 5} end, cache)
    large = String.duplicate("x", 101)
    assert {:ok, ^large} = Cache.fetch(:large, 1000, fn -> {:ok, large} end, cache)
    assert {:ok, 6} = Cache.fetch(:large, 1000, fn -> {:ok, 6} end, cache)
  end
end
