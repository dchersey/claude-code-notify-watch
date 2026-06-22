defmodule ClaudeWatch.TabCacheTest do
  use ExUnit.Case, async: false

  alias ClaudeWatch.TabCache

  # Poll until `fun` is true (the cache refreshes asynchronously).
  defp eventually(fun, tries \\ 50) do
    Enum.reduce_while(1..tries, false, fn _, _ ->
      if fun.(), do: {:halt, true}, else: Process.sleep(20) && {:cont, false}
    end)
  end

  test "is safe (returns nil / :ok) when the cache isn't running" do
    assert TabCache.tab("sess", "1") == nil
    assert TabCache.warm("sess", "1") == :ok
  end

  test "nil session or pane_id short-circuits to nil without touching the server" do
    assert TabCache.tab(nil, "1") == nil
    assert TabCache.tab("sess", nil) == nil
  end

  test "resolves pane_id -> tab via the fetcher and caches it" do
    me = self()

    fetcher = fn session ->
      send(me, {:fetched, session})
      %{"5" => "A", "6" => "B"}
    end

    start_supervised!({TabCache, fetcher: fetcher})

    # Cold: returns nil now but triggers an async refresh.
    assert TabCache.tab("sess", "5") == nil
    assert_receive {:fetched, "sess"}, 1_000

    # Once the refresh lands, panes resolve from cache.
    assert eventually(fn -> TabCache.tab("sess", "5") == "A" end)
    assert TabCache.tab("sess", "6") == "B"
    # Unknown pane in a fresh map → nil (no crash).
    assert TabCache.tab("sess", "999") == nil
  end

  test "a fetcher error leaves the cache empty (nil), not crashing" do
    start_supervised!({TabCache, fetcher: fn _ -> :error end})
    assert TabCache.tab("sess", "5") == nil
    Process.sleep(50)
    assert TabCache.tab("sess", "5") == nil
  end
end
