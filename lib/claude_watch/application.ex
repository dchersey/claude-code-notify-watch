defmodule ClaudeWatch.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    start_workers? =
      System.get_env("CLAUDE_WATCH_NO_SERVER") != "1" and
        Application.get_env(:claude_watch, :start_workers, true)

    children =
      if start_workers? do
        port = Application.get_env(:claude_watch, :api_port, 4747)
        ip = Application.get_env(:claude_watch, :bind_ip, {127, 0, 0, 1})

        ([ClaudeWatch.Notifier, ClaudeWatch.Tokens] ++ maybe_apns()) ++
          [{Bandit, plug: ClaudeWatch.API.Router, scheme: :http, ip: ip, port: port}]
      else
        []
      end

    opts = [strategy: :one_for_one, name: ClaudeWatch.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Start the APNs dispatcher only when its config is present (set in
  # config/runtime.exs once a .p8 + key id + team id are available). Lets the
  # relay run on the pushover/ntfy/log backends with no APNs configured.
  defp maybe_apns do
    if Application.get_env(:claude_watch, ClaudeWatch.APNS), do: [ClaudeWatch.APNS], else: []
  end
end
