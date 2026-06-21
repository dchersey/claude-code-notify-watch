defmodule ClaudeWatch.Delivery.Pushover do
  @moduledoc """
  Pushover (https://pushover.net) — has a native Apple Watch app, so it's the most
  reliable path to the wrist. Needs an app API token + your user key:

    token: env PUSHOVER_TOKEN / keychain "claude-watch-pushover-token"
    user:  env PUSHOVER_USER  / keychain "claude-watch-pushover-user"
  """
  @behaviour ClaudeWatch.Delivery

  @url "https://api.pushover.net/1/messages.json"

  @impl true
  def send(%{title: title, body: body, priority: pri}) do
    with token when is_binary(token) <-
           ClaudeWatch.Secrets.get("PUSHOVER_TOKEN", "claude-watch-pushover-token"),
         user when is_binary(user) <-
           ClaudeWatch.Secrets.get("PUSHOVER_USER", "claude-watch-pushover-user") do
      form = [
        token: token,
        user: user,
        title: title,
        message: body,
        priority: pushover_priority(pri)
      ]

      case Req.post(@url, form: form, receive_timeout: 5_000, retry: false) do
        {:ok, %{status: 200}} -> :ok
        {:ok, resp} -> {:error, {:http, resp.status}}
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> {:error, :missing_pushover_credentials}
    end
  rescue
    e -> {:error, e}
  end

  # high → 1 (bypasses quiet hours, buzzes the watch); normal → 0.
  defp pushover_priority(:high), do: 1
  defp pushover_priority(_), do: 0
end
