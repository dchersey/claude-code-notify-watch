defmodule ClaudeWatch.Notifier do
  @moduledoc """
  Receives Claude Code events and delivers a single, debounced notification per
  logical event to the configured push backend. Per-key `Process.send_after`
  timers collapse bursts (mirrors `LgaPredictor.Actuator`'s timer coalescing):

    * done       — coalesce per session_id over `:done_window_ms` (latest wins)
    * permission — short dedup (`:permission_window_ms`); blocking → fast + high priority
    * subagent   — rate-limited per session (`:subagent_min_gap_ms`)

  Delivery is best-effort: a failed push logs and is dropped — this process must
  never crash the supervisor over a flaky network or a bad token.
  """

  use GenServer
  require Logger

  alias ClaudeWatch.Delivery

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Enqueue a (validated, normalized) event map. Fire-and-forget."
  def event(ev), do: GenServer.cast(__MODULE__, {:event, ev})

  @impl true
  def init(_opts) do
    {:ok, %{timers: %{}, pending: %{}, last_sent: %{}}}
  end

  @impl true
  def handle_cast({:event, %{kind: kind, session_id: sid} = ev}, state) do
    key = {kind, sid}

    # Warm the zellij tab cache now so its (slow) list-panes refresh overlaps the
    # debounce window — the tab is usually resolved by the time we deliver.
    ClaudeWatch.TabCache.warm(ev[:zellij_session], ev[:pane_id])

    # A "done" ends the turn — a subagent that finished just before it (the turn's
    # last action) is redundant, so suppress any still-pending subagent for this
    # session. A subagent with no "done" close behind it still fires (a standalone
    # "subagent finished while Claude keeps working" progress ping).
    state = if kind == "done", do: cancel(state, {"subagent", sid}), else: state

    delay =
      if kind == "subagent" and rate_limited?(state, key),
        do: max(remaining_gap(state, key), delay_for("subagent")),
        else: delay_for(kind)

    {:noreply, arm(state, key, ev, delay)}
  end

  @impl true
  def handle_info({:fire, key}, state) do
    {ev, pending} = Map.pop(state.pending, key)
    state = %{state | pending: pending, timers: Map.delete(state.timers, key)}

    state =
      if ev do
        deliver(ev)
        %{state | last_sent: Map.put(state.last_sent, key, mono())}
      else
        state
      end

    {:noreply, state}
  end

  ## internals

  # Stash the latest event for this key and (re)arm its timer — a newer event in
  # the window replaces the pending one, so only the latest fires.
  defp arm(state, key, ev, delay) do
    if ref = state.timers[key], do: Process.cancel_timer(ref)
    ref = Process.send_after(self(), {:fire, key}, max(delay, 0))
    %{state | timers: Map.put(state.timers, key, ref), pending: Map.put(state.pending, key, ev)}
  end

  # Drop a pending event + its timer (used to suppress a subagent when a done lands).
  defp cancel(state, key) do
    if ref = state.timers[key], do: Process.cancel_timer(ref)
    %{state | timers: Map.delete(state.timers, key), pending: Map.delete(state.pending, key)}
  end

  defp delay_for("permission"), do: cfg(:permission_window_ms, 1_500)
  defp delay_for("done"), do: cfg(:done_window_ms, 8_000)
  defp delay_for("subagent"), do: cfg(:subagent_suppress_window_ms, 8_000)
  defp delay_for(_), do: 1_000

  defp rate_limited?(state, key) do
    case state.last_sent[key] do
      nil -> false
      t -> mono() - t < cfg(:subagent_min_gap_ms, 20_000)
    end
  end

  defp remaining_gap(state, key) do
    gap = cfg(:subagent_min_gap_ms, 20_000)
    max(gap - (mono() - (state.last_sent[key] || 0)), cfg(:subagent_debounce_ms, 1_000))
  end

  # Best-effort delivery; never raise.
  defp deliver(ev) do
    {title, body0} = format(ev)
    body = if body0 in [nil, ""], do: title, else: body0
    msg = %{title: title, body: body, kind: ev.kind, priority: priority_for(ev.kind)}

    case Delivery.send(msg) do
      :ok ->
        Logger.info("[notifier] delivered #{ev.kind} (#{ev.project || ev.session_id})")

      {:error, reason} ->
        Logger.warning("[notifier] delivery failed (#{ev.kind}): #{inspect(reason)}")
    end
  rescue
    e -> Logger.warning("[notifier] delivery crashed: #{inspect(e)}")
  end

  defp format(%{kind: "done", message: msg} = ev),
    do: {"✅ #{label(ev)} — done", body_text(msg, "waiting for your input")}

  defp format(%{kind: "permission", message: msg} = ev),
    do: {"🔐 #{label(ev)} — approve?", body_text(msg, "needs your approval")}

  defp format(%{kind: "subagent", agent_type: agent, message: msg} = ev),
    do: {"🤖 #{agent || "subagent"} done — #{label(ev)}", body_text(msg, "subagent finished")}

  defp format(%{message: msg} = ev), do: {label(ev), body_text(msg, "")}

  # "<project>:<tab>" when the zellij tab is known, else just "<project>". The tab
  # is resolved live from zellij (cached in ClaudeWatch.TabCache via pane_id +
  # zellij_session), falling back to a hook-supplied `tab` if present.
  defp label(ev) do
    base = ev[:project] || "Claude"

    case ClaudeWatch.TabCache.tab(ev[:zellij_session], ev[:pane_id]) || ev[:tab] do
      t when is_binary(t) and t != "" -> "#{base}:#{t}"
      _ -> base
    end
  end

  # Use the message when present, else a sensible per-kind default (Pushover
  # requires a non-empty message, and it's nicer than echoing the title).
  defp body_text(s, _default) when is_binary(s) and s != "" do
    max = cfg(:max_body_len, 200)
    if String.length(s) > max, do: String.slice(s, 0, max - 1) <> "…", else: s
  end

  defp body_text(_, default), do: default

  # Coarse priority; each adapter maps it to its own scale.
  defp priority_for("permission"), do: :high
  defp priority_for(_), do: :normal

  defp cfg(k, d), do: Application.get_env(:claude_watch, k, d)
  defp mono, do: System.monotonic_time(:millisecond)
end
