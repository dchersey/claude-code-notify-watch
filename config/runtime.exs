import Config

# Read at boot so the LaunchAgent can be repointed via env without editing source.
# Secrets themselves (Pushover token/user, ntfy topic/token, Bark key) are read
# lazily at send time by ClaudeWatch.Secrets (ENV or macOS Keychain) — not here.
if config_env() != :test do
  if backend = System.get_env("CLAUDE_WATCH_BACKEND") do
    config :claude_watch, :delivery_backend, backend
  end

  if port = System.get_env("CLAUDE_WATCH_PORT") do
    config :claude_watch, :api_port, String.to_integer(port)
  end

  # Read a value from the login Keychain — a fallback for secrets so they need not
  # live in the LaunchAgent plist. Inlined (not ClaudeWatch.Secrets) to avoid
  # app-module load-order assumptions during config evaluation. Trimmed.
  kc = fn service ->
    case System.cmd("security", ["find-generic-password", "-s", service, "-w"],
           stderr_to_stdout: true
         ) do
      {out, 0} -> String.trim(out)
      _ -> nil
    end
  end

  # Shared secret: ENV first, then Keychain (claude-watch-shared-secret). Trimmed —
  # a stray newline would 401 every request.
  case System.get_env("CLAUDE_WATCH_SECRET") || kc.("claude-watch-shared-secret") do
    s when is_binary(s) ->
      case String.trim(s) do
        "" -> :ok
        v -> config :claude_watch, :shared_secret, v
      end

    _ ->
      :ok
  end

  # Override where device tokens persist (default ~/Library/Application Support/...).
  if tp = System.get_env("CLAUDE_WATCH_TOKENS_PATH") do
    config :claude_watch, :tokens_path, tp
  end

  # Bind address (e.g. CLAUDE_WATCH_BIND=0.0.0.0 so the app can register over LAN).
  if bind = System.get_env("CLAUDE_WATCH_BIND") do
    ip = bind |> String.split(".") |> Enum.map(&String.to_integer/1) |> List.to_tuple()
    config :claude_watch, :bind_ip, ip
  end

  # Optional tuning: lower the "done" coalesce/debounce window (ms) for snappier
  # "done" pings (default 8000). Independent of subagent suppression, which keys
  # off a "done" arriving — not firing — so a small value is safe.
  if v = System.get_env("CLAUDE_WATCH_DONE_WINDOW_MS") do
    case Integer.parse(v) do
      {ms, _} when ms >= 0 -> config :claude_watch, :done_window_ms, ms
      _ -> :ok
    end
  end

  # APNs dispatcher (delivery_backend "apns"): configure Pigeon from a .p8 file +
  # key id / team id (env, else login Keychain). Skipped unless the .p8 exists, so
  # the relay still boots on pushover/ntfy/log with no APNs configured. Always :prod.
  apns_key_path =
    System.get_env("CLAUDE_WATCH_APNS_KEY_PATH") ||
      Path.join([
        System.user_home() || ".",
        "Library",
        "Application Support",
        "claude-watch",
        "AuthKey.p8"
      ])

  if File.exists?(apns_key_path) do
    key_id = System.get_env("CLAUDE_WATCH_APNS_KEY_ID") || kc.("claude-watch-apns-key-id")
    team_id = System.get_env("CLAUDE_WATCH_APNS_TEAM_ID") || kc.("claude-watch-apns-team-id")

    if is_binary(key_id) and is_binary(team_id) do
      case System.get_env("CLAUDE_WATCH_APNS_TOPIC") do
        t when is_binary(t) and t != "" -> config :claude_watch, :apns_topic, t
        _ -> :ok
      end

      config :claude_watch, ClaudeWatch.APNS,
        adapter: Pigeon.APNS,
        key: File.read!(apns_key_path),
        key_identifier: key_id,
        team_id: team_id,
        mode: :prod
    end
  end
end
