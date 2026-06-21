defmodule ClaudeWatch.Delivery.Ntfy do
  @moduledoc """
  ntfy (https://ntfy.sh or self-hosted). Free; reaches the watch via iPhone
  notification mirroring (no dedicated watch app). The topic is the address —
  keep it long and unguessable.

    base:  config :ntfy_base (default "https://ntfy.sh")
    topic: env NTFY_TOPIC / keychain "claude-watch-ntfy-topic"
    auth (optional, self-hosted): env NTFY_TOKEN / keychain "claude-watch-ntfy-token"

  HTTP header values must be Latin-1, so the (emoji-bearing) title is sent
  ASCII-sanitized in the `Title` header; the emoji ride along via `Tags`
  shortcodes, and the UTF-8 message goes in the request body.
  """
  @behaviour ClaudeWatch.Delivery

  @impl true
  def send(%{title: title, body: body, kind: kind, priority: pri}) do
    case ClaudeWatch.Secrets.get("NTFY_TOPIC", "claude-watch-ntfy-topic") do
      topic when is_binary(topic) ->
        base = Application.get_env(:claude_watch, :ntfy_base, "https://ntfy.sh")
        url = base <> "/" <> topic

        headers =
          [
            {"title", ascii(title)},
            {"priority", ntfy_priority(pri)},
            {"tags", ntfy_tags(kind)}
          ] ++ auth_header()

        case Req.post(url, headers: headers, body: body, receive_timeout: 5_000, retry: false) do
          {:ok, %{status: s}} when s in 200..299 -> :ok
          {:ok, resp} -> {:error, {:http, resp.status}}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :missing_ntfy_topic}
    end
  rescue
    e -> {:error, e}
  end

  defp auth_header do
    case ClaudeWatch.Secrets.get("NTFY_TOKEN", "claude-watch-ntfy-token") do
      t when is_binary(t) -> [{"authorization", "Bearer " <> t}]
      _ -> []
    end
  end

  defp ntfy_priority(:high), do: "urgent"
  defp ntfy_priority(_), do: "default"

  defp ntfy_tags("permission"), do: "lock"
  defp ntfy_tags("subagent"), do: "robot"
  defp ntfy_tags(_), do: "white_check_mark"

  # Strip to ASCII for the header: em-dash → "-", drop emoji/other non-ASCII,
  # collapse whitespace.
  defp ascii(s) do
    s
    |> String.replace("—", "-")
    |> String.replace(~r/[^\x00-\x7F]/u, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
