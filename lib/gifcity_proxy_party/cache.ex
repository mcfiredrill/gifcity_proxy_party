defmodule GifcityProxyParty.Cache do
  @moduledoc "Bounded node-local TTL cache with shared in-flight fetches."
  use GenServer

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def fetch(key, ttl, fun, server \\ __MODULE__),
    do: GenServer.call(server, {:fetch, key, ttl, fun}, 20_000)

  @impl true
  def init(opts) do
    {:ok,
     %{
       entries: %{},
       pending: %{},
       max_entries: Keyword.get(opts, :max_entries, 500),
       max_bytes: Keyword.get(opts, :max_bytes, 64 * 1024 * 1024)
     }}
  end

  @impl true
  def handle_call({:fetch, key, ttl, fun}, from, state) do
    entries = Map.reject(state.entries, fn {_, {expires, _, _}} -> expires <= now() end)
    state = %{state | entries: entries}

    case entries[key] do
      {_, value, _} ->
        {:reply, {:ok, value}, state}

      nil ->
        cond do
          Map.has_key?(state.pending, key) ->
            if length(state.pending[key].waiters) >= 100 do
              {:reply, {:error, :busy}, state}
            else
              {:noreply, update_in(state.pending[key].waiters, &[from | &1])}
            end

          map_size(state.pending) >= 16 ->
            {:reply, {:error, :busy}, state}

          true ->
            task = Task.Supervisor.async_nolink(GifcityProxyParty.Tasks, fun)
            timer = Process.send_after(self(), {:timeout, key, task.ref}, 15_000)
            pending = %{ref: task.ref, pid: task.pid, timer: timer, ttl: ttl, waiters: [from]}
            {:noreply, put_in(state.pending[key], pending)}
        end
    end
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    finish(ref, result, state)
  end

  def handle_info({:DOWN, ref, :process, _, _}, state),
    do: finish(ref, {:error, :upstream}, state)

  def handle_info({:timeout, key, ref}, state) do
    case state.pending[key] do
      %{ref: ^ref, pid: pid} ->
        Process.exit(pid, :kill)
        finish(ref, {:error, :timeout}, state)

      _ ->
        {:noreply, state}
    end
  end

  defp finish(ref, result, state) do
    case Enum.find(state.pending, fn {_, pending} -> pending.ref == ref end) do
      nil ->
        {:noreply, state}

      {key, pending} ->
        Process.cancel_timer(pending.timer)
        Enum.each(pending.waiters, &GenServer.reply(&1, result))
        state = %{state | pending: Map.delete(state.pending, key)}

        entries =
          case result do
            {:ok, value} ->
              size = :erlang.external_size(value)

              if size <= state.max_bytes do
                state.entries |> Map.put(key, {now() + pending.ttl, value, size}) |> trim(state)
              else
                state.entries
              end

            _ ->
              state.entries
          end

        {:noreply, %{state | entries: entries}}
    end
  end

  defp trim(entries, state) do
    bytes = Enum.reduce(entries, 0, fn {_, {_, _, size}}, acc -> acc + size end)

    if map_size(entries) > state.max_entries or bytes > state.max_bytes do
      {key, _} = Enum.min_by(entries, fn {_, {expires, _, _}} -> expires end)
      trim(Map.delete(entries, key), state)
    else
      entries
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
