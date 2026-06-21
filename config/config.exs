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
  # Debounce windows (ms) — collapse bursts so the watch isn't spammed.
  done_window_ms: 8_000,
  permission_window_ms: 1_500,
  # Hold a subagent-finished event this long; if a "done" for the same session
  # arrives within it, the subagent was the turn's last action → suppressed (the
  # "done" covers it). A standalone subagent (no done close behind) still fires.
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
