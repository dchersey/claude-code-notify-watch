defmodule ClaudeWatch do
  @moduledoc """
  Claude Code → Apple Watch notifier.

  A small localhost relay: Claude Code hooks POST events to
  `http://127.0.0.1:4747/claude/event`; the `Notifier` GenServer debounces them
  and a pluggable `Delivery` backend (Pushover / ntfy / Bark) pushes a concise
  notification to your watch. See README.md.
  """
end
