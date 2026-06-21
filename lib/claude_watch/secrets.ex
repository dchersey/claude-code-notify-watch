defmodule ClaudeWatch.Secrets do
  @moduledoc """
  Resolve a secret from ENV first, then the macOS login Keychain. ALWAYS trims —
  a stray trailing newline (common when piping a value via `echo`, or pasting)
  makes byte-exact credential checks fail (Pushover token, ntfy auth). See the
  global note in ~/.claude/CLAUDE.md.
  """

  @doc "Trimmed secret from ENV `env` or Keychain `keychain_service`, else nil."
  def get(env, keychain_service) do
    raw = System.get_env(env) || ClaudeWatch.Keychain.get(keychain_service, env)

    case raw do
      s when is_binary(s) ->
        case String.trim(s) do
          "" -> nil
          v -> v
        end

      _ ->
        nil
    end
  end
end
