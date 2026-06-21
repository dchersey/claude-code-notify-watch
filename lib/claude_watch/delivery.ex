defmodule ClaudeWatch.Delivery do
  @moduledoc """
  Pluggable push backend, selected by the `:delivery_backend` config
  ("log" | "pushover" | "ntfy" | "bark"). The Notifier hands a backend-agnostic
  message; each adapter maps `priority` (`:normal | :high`) to its own scale.
  """

  @type msg :: %{
          title: String.t(),
          body: String.t(),
          kind: String.t(),
          priority: :normal | :high
        }

  @callback send(msg) :: :ok | {:error, term}

  @adapters %{
    "log" => ClaudeWatch.Delivery.Log,
    "ntfy" => ClaudeWatch.Delivery.Ntfy,
    "pushover" => ClaudeWatch.Delivery.Pushover,
    "bark" => ClaudeWatch.Delivery.Bark
  }

  @spec send(msg) :: :ok | {:error, term}
  def send(msg), do: adapter().send(msg)

  def adapter do
    name = Application.get_env(:claude_watch, :delivery_backend, "log")
    Map.get(@adapters, name, ClaudeWatch.Delivery.Log)
  end
end
