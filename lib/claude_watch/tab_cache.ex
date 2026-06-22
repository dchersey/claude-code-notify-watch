defmodule ClaudeWatch.TabCache do
  @moduledoc """
  Resolves a zellij `pane_id` → tab name for notification labels — WITHOUT making
  the hook pay zellij's ~2s `list-panes` latency on every event (that delay both
  raced the hook's timeout, dropping the tab, and added ~2s of notification lag).

  The hook now just sends its `pane_id` + zellij `session`; this cache runs
  `zellij --session <s> action list-panes --json` OFF the critical path, memoizes
  the per-session `pane_id => tab_name` map, and refreshes asynchronously. Lookups
  return instantly (cached, possibly slightly stale — tab assignments are stable)
  and never block the Notifier. A miss for an unknown pane triggers a bounded
  background refresh, so a freshly-created pane is picked up within a couple of
  seconds. Degrades to nil (no tab suffix) when zellij isn't present.
  """
  use GenServer
  require Logger

  @ttl_ms 8_000
  # Don't re-fetch a session more often than this when a pane is merely missing
  # (a new pane) — bounds refreshes for a pane id that never appears.
  @miss_retry_ms 2_500
  @fetch_timeout_ms 6_000

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Tab name for (session, pane_id), or nil. Instant: returns the cached value and
  triggers an async refresh when the entry is stale or the pane is unknown. Safe
  to call when the cache isn't running (returns nil).
  """
  def tab(session, pane_id) when is_binary(session) and is_binary(pane_id) do
    case GenServer.whereis(__MODULE__) do
      nil -> nil
      pid -> GenServer.call(pid, {:tab, session, pane_id})
    end
  catch
    :exit, _ -> nil
  end

  def tab(_, _), do: nil

  @doc "Pre-warm a session's cache (cast; non-blocking). No-op if not running."
  def warm(session, pane_id) when is_binary(session) and is_binary(pane_id) do
    if pid = GenServer.whereis(__MODULE__), do: GenServer.cast(pid, {:warm, session, pane_id})
    :ok
  end

  def warm(_, _), do: :ok

  # --- Server ---

  @impl true
  def init(opts) do
    # Injectable for tests: a 1-arg fun session -> %{pane_id => tab} | :error.
    fetcher = Keyword.get(opts, :fetcher, &fetch_panes/1)
    {:ok, %{fetcher: fetcher, sessions: %{}, inflight: MapSet.new()}}
  end

  @impl true
  def handle_call({:tab, session, pane_id}, _from, state) do
    entry = state.sessions[session]
    state = if needs_refresh?(entry, pane_id), do: trigger(state, session), else: state
    {:reply, entry && Map.get(entry.panes, pane_id), state}
  end

  @impl true
  def handle_cast({:warm, session, pane_id}, state) do
    entry = state.sessions[session]
    {:noreply, if(needs_refresh?(entry, pane_id), do: trigger(state, session), else: state)}
  end

  def handle_cast({:refreshed, session, panes}, state) do
    sessions =
      if is_map(panes),
        do: Map.put(state.sessions, session, %{panes: panes, at: mono()}),
        else: state.sessions

    {:noreply, %{state | sessions: sessions, inflight: MapSet.delete(state.inflight, session)}}
  end

  defp needs_refresh?(nil, _pane_id), do: true

  defp needs_refresh?(%{at: at, panes: panes}, pane_id) do
    age = mono() - at
    age > @ttl_ms or (not Map.has_key?(panes, pane_id) and age > @miss_retry_ms)
  end

  # Fire the (slow) fetch in a Task so the GenServer never blocks; dedup per session.
  defp trigger(state, session) do
    if MapSet.member?(state.inflight, session) do
      state
    else
      parent = self()
      fetcher = state.fetcher
      Task.start(fn -> GenServer.cast(parent, {:refreshed, session, fetcher.(session)}) end)
      %{state | inflight: MapSet.put(state.inflight, session)}
    end
  end

  # `zellij --session <s> action list-panes --json` → %{pane_id_string => tab_name}
  # | :error. Bounded so a wedged zellij can't leak a forever-running Task.
  defp fetch_panes(session) do
    case zellij_bin() do
      nil ->
        :error

      zj ->
        task =
          Task.async(fn ->
            System.cmd(zj, ["--session", session, "action", "list-panes", "--json"],
              stderr_to_stdout: true
            )
          end)

        case Task.yield(task, @fetch_timeout_ms) || Task.shutdown(task) do
          {:ok, {out, 0}} -> parse(out)
          _ -> :error
        end
    end
  rescue
    _ -> :error
  end

  defp parse(json) do
    case Jason.decode(json) do
      {:ok, panes} when is_list(panes) ->
        for %{"id" => id, "tab_name" => t} = p <- panes,
            p["is_plugin"] != true,
            is_binary(t) and t != "",
            into: %{},
            do: {to_string(id), t}

      _ ->
        :error
    end
  end

  defp zellij_bin do
    [
      Path.join([System.user_home() || "", ".local", "bin", "zellij"]),
      "/opt/homebrew/bin/zellij",
      "/usr/local/bin/zellij"
    ]
    |> Enum.find(&File.exists?/1)
    |> case do
      nil -> System.find_executable("zellij")
      path -> path
    end
  end

  defp mono, do: System.monotonic_time(:millisecond)
end
