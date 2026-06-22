defmodule ClaudeWatch.Notifier do
  @moduledoc """
  Receives Claude Code events and delivers a single, debounced notification per
  logical event to the configured push backend. Per-key `Process.send_after`
  timers collapse bursts (mirrors `LgaPredictor.Actuator`'s timer coalescing):

    * done       — delivered immediately (`:done_window_ms` 0; >0 coalesces a burst)
    * permission — short dedup (`:permission_window_ms`); blocking → fast + high priority
    * subagent   — NOT relayed unless `:relay_subagent` is true; then rate-limited
                   (`:subagent_min_gap_ms`) and suppressed by a trailing "done"

  The first event for an as-yet-unresolved zellij pane is held and polled until its
  `<tab>:<session>` label resolves (capped by `:cold_label_max_ms`), then delivered;
  warm panes and non-zellij events deliver on their normal schedule.

  Delivery is best-effort: a failed push logs and is dropped — this process must
  never crash the supervisor over a flaky network or a bad token.
  """

  use GenServer
  require Logger

  alias ClaudeWatch.Delivery

  # Poll interval while holding a cold event until its session-name label resolves.
  @poll_ms 250

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Enqueue a (validated, normalized) event map. Fire-and-forget."
  def event(ev), do: GenServer.cast(__MODULE__, {:event, ev})

  @impl true
  def init(_opts) do
    {:ok, %{timers: %{}, pending: %{}, last_sent: %{}}}
  end

  @impl true
  def handle_cast({:event, %{kind: kind, session_id: sid} = ev}, state) do
    cond do
      # Subagent pings are off by default (noisy); drop unless explicitly enabled.
      kind == "subagent" and not relay_subagent?() ->
        {:noreply, state}

      true ->
        key = {kind, sid}

        # Look up the cached label now; this also triggers an async refresh when the
        # pane isn't cached yet, so the slow zellij lookup overlaps our delay below.
        info = ClaudeWatch.TabCache.info(ev[:zellij_session], ev[:pane_id])

        # A "done" ends the turn — a subagent that finished just before it (the turn's
        # last action) is redundant, so suppress any still-pending subagent for this
        # session. (Only relevant when subagents are relayed.)
        state = if kind == "done", do: cancel(state, {"subagent", sid}), else: state

        # The FIRST event for a not-yet-resolved zellij pane is held and polled until
        # its session-name label lands (capped by :cold_label_max_ms), so it carries
        # "<tab>:<session>" rather than just the folder. Warm panes + non-zellij
        # events keep their normal (often immediate) schedule.
        {ev, base} =
          if cold_label?(ev, info),
            do:
              {Map.put(ev, :__label_deadline, mono() + cfg(:cold_label_max_ms, 5_000)), @poll_ms},
            else: {ev, delay_for(kind)}

        delay =
          if kind == "subagent" and rate_limited?(state, key),
            do: max(remaining_gap(state, key), base),
            else: base

        {:noreply, arm(state, key, ev, delay)}
    end
  end

  @impl true
  def handle_info({:fire, key}, state) do
    {ev, pending} = Map.pop(state.pending, key)
    state = %{state | pending: pending, timers: Map.delete(state.timers, key)}

    cond do
      is_nil(ev) ->
        {:noreply, state}

      # Still holding for the session-name label (within deadline) → poll again.
      label_pending?(ev) ->
        {:noreply, arm(state, key, ev, @poll_ms)}

      true ->
        deliver(ev)
        {:noreply, %{state | last_sent: Map.put(state.last_sent, key, mono())}}
    end
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
  defp delay_for("done"), do: cfg(:done_window_ms, 0)
  defp delay_for("subagent"), do: cfg(:subagent_suppress_window_ms, 8_000)
  defp delay_for(_), do: 1_000

  defp relay_subagent?, do: cfg(:relay_subagent, false)

  # A first event worth holding for its label: a zellij pane (session + pane id)
  # whose label isn't cached yet.
  defp cold_label?(ev, info),
    do: is_nil(info) and present?(ev[:zellij_session]) and present?(ev[:pane_id])

  # True while a held event's label still isn't resolved and its deadline is in the
  # future — re-checking the cache (which keeps the async refresh alive).
  defp label_pending?(ev) do
    case ev[:__label_deadline] do
      nil ->
        false

      deadline ->
        mono() < deadline and
          is_nil(ClaudeWatch.TabCache.info(ev[:zellij_session], ev[:pane_id]))
    end
  end

  defp present?(s), do: is_binary(s) and s != ""

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

    # collapse_id = the Claude session, so each session shows a single notification
    # (the latest replaces the prior) instead of stacking. Backends that don't
    # support collapsing ignore it.
    msg = %{
      title: title,
      body: body,
      kind: ev.kind,
      priority: priority_for(ev.kind),
      collapse_id: ev[:session_id]
    }

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

  # "<tab>:<name>" where name is the Claude session slug (from the pane title,
  # resolved live + cached in ClaudeWatch.TabCache) when known, else the project
  # (folder) — e.g. "A:apple-watch-apns-delivery", or "A:zellij" as a fallback.
  # The session slug distinguishes sessions far better than the folder when many
  # share a directory. Drops to just "<name>" outside zellij.
  defp label(ev) do
    info = ClaudeWatch.TabCache.info(ev[:zellij_session], ev[:pane_id])
    tab = (info && info.tab) || ev[:tab]
    name = clamp((info && info.slug) || ev[:project] || "Claude", 32)

    case tab do
      t when is_binary(t) and t != "" -> "#{t}:#{name}"
      _ -> name
    end
  end

  # Cap the label name so a long session summary still fits a notification.
  defp clamp(s, max) when is_binary(s) and byte_size(s) > 0 do
    if String.length(s) > max, do: String.slice(s, 0, max - 1) <> "…", else: s
  end

  defp clamp(s, _), do: s

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
