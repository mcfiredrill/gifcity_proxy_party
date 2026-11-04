defmodule GifcityProxyParty.FakeHTTP do
  use Agent
  def start_link(_), do: Agent.start_link(fn -> %{handler: nil, calls: []} end, name: __MODULE__)
  def stub(fun), do: Agent.update(__MODULE__, &%{&1 | handler: fun})
  def calls, do: Agent.get(__MODULE__, &Enum.reverse(&1.calls))

  def get(url, limit) do
    fun =
      Agent.get_and_update(__MODULE__, fn state ->
        {state.handler, %{state | calls: [url | state.calls]}}
      end)

    fun.(url, limit)
  end
end
