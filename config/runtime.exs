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

  # Trimmed — a stray newline here would 401 every request.
  case System.get_env("CLAUDE_WATCH_SECRET") do
    s when is_binary(s) ->
      case String.trim(s) do
        "" -> :ok
        v -> config :claude_watch, :shared_secret, v
      end

    _ ->
      :ok
  end
end
