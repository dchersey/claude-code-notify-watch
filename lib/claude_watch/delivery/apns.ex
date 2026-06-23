defmodule ClaudeWatch.Delivery.Apns do
  @moduledoc """
  Native APNs delivery via Pigeon — direct to Apple, no third-party queue (the
  fast, self-owned path). Pushes to every device token registered via
  `POST /register` (`ClaudeWatch.Tokens`), and evicts tokens APNs reports as
  bad/unregistered. Send + eviction logic mirrors option-trader's
  `Trader.WatchPusher.send_notification/4`.

  Requires the APNs dispatcher to be configured + started (see
  `ClaudeWatch.APNS` / `config/runtime.exs`).
  """
  @behaviour ClaudeWatch.Delivery
  require Logger

  @impl true
  def send(%{title: title, body: body, priority: priority} = msg) do
    case ClaudeWatch.Tokens.all() do
      [] ->
        Logger.warning(
          "[delivery:apns] no registered tokens — open the Claude Code app to register"
        )

        {:error, :no_tokens}

      tokens ->
        case Application.get_env(:claude_watch, :apns_topic) do
          topic when is_binary(topic) and topic != "" ->
            collapse_id = msg[:collapse_id]
            results = Enum.map(tokens, &push_one(&1, title, body, priority, topic, collapse_id))
            if Enum.any?(results, &(&1 == :ok)), do: :ok, else: {:error, :all_failed}

          _ ->
            Logger.error(
              "[delivery:apns] :apns_topic not set (set CLAUDE_WATCH_APNS_TOPIC) — cannot push"
            )

            {:error, :no_topic}
        end
    end
  rescue
    e -> {:error, e}
  end

  defp push_one(token, title, body, priority, topic, collapse_id) do
    import Pigeon.APNS.Notification

    notification =
      new("", token, topic)
      |> put_alert(%{"title" => title, "body" => body})
      |> put_sound(Application.get_env(:claude_watch, :apns_sound, "default"))
      |> put_custom(%{"interruption-level" => level(priority)})
      |> collapse(collapse_id)

    case ClaudeWatch.APNS.push(notification) do
      %Pigeon.APNS.Notification{response: :success} ->
        :ok

      %Pigeon.APNS.Notification{response: resp} when resp in [:bad_device_token, :unregistered] ->
        Logger.info("[delivery:apns] evicting invalid token (#{resp})")
        ClaudeWatch.Tokens.delete(token)
        {:error, resp}

      %Pigeon.APNS.Notification{response: resp} ->
        Logger.warning("[delivery:apns] push failed: #{inspect(resp)}")
        {:error, resp}

      other ->
        Logger.warning("[delivery:apns] unexpected APNs result: #{inspect(other)}")
        {:error, :unexpected}
    end
  end

  # Collapse same-session notifications into one (latest replaces prior, via the
  # apns-collapse-id header) so a session never stacks on the lock screen / watch.
  defp collapse(notification, id) when is_binary(id) and id != "",
    do: %{notification | collapse_id: id}

  defp collapse(notification, _), do: notification

  # permission is blocking → time-sensitive (breaks through Focus); else active.
  defp level(:high), do: "time-sensitive"
  defp level(_), do: "active"
end
