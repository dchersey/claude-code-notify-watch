import Config

config :claude_watch,
  api_port: 4747,
  # Delivery backend (see lib/claude_watch/delivery/*). Default "log" for safe
  # bring-up — it just logs the would-be push so the service runs without any
  # credentials. Switch to "pushover" (native Apple Watch app, most reliable),
  # "ntfy" (free / self-hostable), or "bark" once you've added creds + installed
  # the matching iOS app. Override at runtime with CLAUDE_WATCH_BACKEND.
  delivery_backend: "pushover",
  ntfy_base: "https://ntfy.sh",
  bark_server: "https://api.day.app",
  # "done" (idle / ready-for-input) fires immediately — no debounce. Set >0 to
  # coalesce a burst of done events per session (latest wins) at the cost of
  # latency. Override at runtime with CLAUDE_WATCH_DONE_WINDOW_MS.
  done_window_ms: 0,
  # Permission prompts dedup over a short window (blocking → kept fast).
  permission_window_ms: 1_500,
  # Subagent-finished pings are NOT relayed by default (noisy). Enable with
  # relay_subagent: true (or CLAUDE_WATCH_SUBAGENT=1). When on, a subagent is
  # suppressed if a "done" for the same session follows within
  # subagent_suppress_window_ms, and rate-limited per session by subagent_min_gap_ms.
  relay_subagent: false,
  subagent_suppress_window_ms: 8_000,
  subagent_min_gap_ms: 20_000,
  max_body_len: 200,
  # HTTP listener bind address. Loopback-only by default; override with
  # CLAUDE_WATCH_BIND (e.g. "0.0.0.0"). Set shared_secret if you expose it.
  bind_ip: {127, 0, 0, 1},
  # Optional shared secret for POST /claude/event (X-Claude-Watch-Secret header).
  # nil = no check. Recommended once bind_ip is off-loopback.
  shared_secret: nil

if config_env() == :test do
  import_config "test.exs"
end
