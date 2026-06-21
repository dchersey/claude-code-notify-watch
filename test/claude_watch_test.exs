defmodule ClaudeWatch.NotifierTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias ClaudeWatch.Notifier

  setup do
    # Tiny windows so tests are fast + deterministic; log backend (no real push).
    Application.put_env(:claude_watch, :delivery_backend, "log")
    Application.put_env(:claude_watch, :done_window_ms, 60)
    Application.put_env(:claude_watch, :permission_window_ms, 30)
    Application.put_env(:claude_watch, :subagent_suppress_window_ms, 120)
    Application.put_env(:claude_watch, :subagent_min_gap_ms, 1_000)
    :ok
  end

  defp ev(attrs) do
    Map.merge(
      %{
        kind: "done",
        session_id: "s",
        project: "p",
        message: nil,
        agent_type: nil,
        cwd: nil,
        ts: nil
      },
      attrs
    )
  end

  defp deliveries(log), do: (log |> String.split("[delivery:log]") |> length()) - 1

  test "coalesces repeated done for one session into a single delivery" do
    log =
      capture_log([level: :info], fn ->
        start_supervised!(Notifier)
        for _ <- 1..3, do: Notifier.event(ev(%{session_id: "s1"}))
        Process.sleep(250)
      end)

    assert deliveries(log) == 1
  end

  test "different sessions each deliver" do
    log =
      capture_log([level: :info], fn ->
        start_supervised!(Notifier)
        Notifier.event(ev(%{session_id: "a"}))
        Notifier.event(ev(%{session_id: "b"}))
        Process.sleep(250)
      end)

    assert deliveries(log) == 2
  end

  test "permission and done are distinct keys → both deliver" do
    log =
      capture_log([level: :info], fn ->
        start_supervised!(Notifier)
        Notifier.event(ev(%{kind: "permission", session_id: "s1", message: "approve rm?"}))
        Notifier.event(ev(%{kind: "done", session_id: "s1"}))
        Process.sleep(250)
      end)

    assert deliveries(log) == 2
  end

  test "subagent is suppressed when a done follows for the same session" do
    log =
      capture_log([level: :info], fn ->
        start_supervised!(Notifier)
        Notifier.event(ev(%{kind: "subagent", session_id: "s1", agent_type: "Explore"}))
        Notifier.event(ev(%{kind: "done", session_id: "s1"}))
        Process.sleep(300)
      end)

    # Only the done lands; the trailing subagent is suppressed.
    assert deliveries(log) == 1
    assert log =~ "done"
    refute log =~ "🤖"
  end

  test "a standalone subagent (no done close behind) still delivers" do
    log =
      capture_log([level: :info], fn ->
        start_supervised!(Notifier)
        Notifier.event(ev(%{kind: "subagent", session_id: "s9", agent_type: "Plan"}))
        Process.sleep(300)
      end)

    assert deliveries(log) == 1
    assert log =~ "🤖"
  end

  test "a done for one session does not suppress another session's subagent" do
    log =
      capture_log([level: :info], fn ->
        start_supervised!(Notifier)
        Notifier.event(ev(%{kind: "subagent", session_id: "s1", agent_type: "Explore"}))
        Notifier.event(ev(%{kind: "done", session_id: "OTHER"}))
        Process.sleep(300)
      end)

    # s1's subagent survives (OTHER's done can't suppress it) → subagent + done.
    assert deliveries(log) == 2
    assert log =~ "🤖"
  end

  test "tab name is appended to the title when present" do
    log =
      capture_log([level: :info], fn ->
        start_supervised!(Notifier)
        Notifier.event(ev(%{kind: "done", session_id: "s1", project: "zellij", tab: "A"}))
        Process.sleep(200)
      end)

    assert log =~ "zellij:A"
  end
end
