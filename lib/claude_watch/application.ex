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

        [
          ClaudeWatch.Notifier,
          {Bandit, plug: ClaudeWatch.API.Router, scheme: :http, ip: {127, 0, 0, 1}, port: port}
        ]
      else
        []
      end

    opts = [strategy: :one_for_one, name: ClaudeWatch.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
