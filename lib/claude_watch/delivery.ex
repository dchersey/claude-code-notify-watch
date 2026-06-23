defmodule ClaudeWatch.Delivery do
  @moduledoc """
  Pluggable push backend, selected by the `:delivery_backend` config
  ("log" | "pushover" | "ntfy" | "bark" | "apns"). The Notifier hands a
  backend-agnostic message; each adapter maps `priority` (`:normal | :high`) to
  its own scale. ("apns" = native, self-owned APNs straight to your own app.)
  """

  @type msg :: %{
          :title => String.t(),
          :body => String.t(),
          :kind => String.t(),
          :priority => :normal | :high,
          # APNs-only extras (other backends ignore them): collapse id (per session)
          # + session/ts for the companion app's dashboard.
          optional(:collapse_id) => String.t() | nil,
          optional(:session) => String.t() | nil,
          optional(:ts) => integer() | nil
        }

  @callback send(msg) :: :ok | {:error, term}

  @adapters %{
    "log" => ClaudeWatch.Delivery.Log,
    "ntfy" => ClaudeWatch.Delivery.Ntfy,
    "pushover" => ClaudeWatch.Delivery.Pushover,
    "bark" => ClaudeWatch.Delivery.Bark,
    "apns" => ClaudeWatch.Delivery.Apns
  }

  @spec send(msg) :: :ok | {:error, term}
  def send(msg), do: adapter().send(msg)

  def adapter do
    name = Application.get_env(:claude_watch, :delivery_backend, "log")
    Map.get(@adapters, name, ClaudeWatch.Delivery.Log)
  end
end
