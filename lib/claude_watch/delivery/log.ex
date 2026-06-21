defmodule ClaudeWatch.Delivery.Log do
  @moduledoc "No-op adapter: logs the would-be push. Default for bring-up + tests."
  @behaviour ClaudeWatch.Delivery
  require Logger

  @impl true
  def send(%{title: title, body: body}) do
    Logger.info("[delivery:log] #{title} — #{body}")
    :ok
  end
end
