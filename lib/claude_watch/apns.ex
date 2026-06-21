defmodule ClaudeWatch.APNS do
  @moduledoc """
  Pigeon APNs dispatcher for the dedicated Claude Code watch app.

  Configured in `config/runtime.exs` (key/.p8 + key id + team id + mode) and
  started in the supervision tree only when that config is present — so the relay
  still runs fine on the `pushover`/`ntfy`/`log` backends with no APNs set up.
  Mirrors option-trader's `Trader.APNS`.
  """
  use Pigeon.Dispatcher, otp_app: :claude_watch
end
