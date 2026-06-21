defmodule ClaudeWatch.Delivery.Bark do
  @moduledoc """
  Bark (https://github.com/Finb/Bark). iOS push via a per-device key; reaches the
  watch via iPhone mirroring (no dedicated watch app).

    server: config :bark_server (default "https://api.day.app")
    key:    env BARK_KEY / keychain "claude-watch-bark-key"
  """
  @behaviour ClaudeWatch.Delivery

  @impl true
  def send(%{title: title, body: body, priority: pri}) do
    case ClaudeWatch.Secrets.get("BARK_KEY", "claude-watch-bark-key") do
      key when is_binary(key) ->
        server = Application.get_env(:claude_watch, :bark_server, "https://api.day.app")
        url = "#{server}/#{key}"
        payload = %{title: title, body: body, level: bark_level(pri)}

        case Req.post(url, json: payload, receive_timeout: 5_000, retry: false) do
          {:ok, %{status: s}} when s in 200..299 -> :ok
          {:ok, resp} -> {:error, {:http, resp.status}}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :missing_bark_key}
    end
  rescue
    e -> {:error, e}
  end

  defp bark_level(:high), do: "timeSensitive"
  defp bark_level(_), do: "active"
end
