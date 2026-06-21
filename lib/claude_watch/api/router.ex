defmodule ClaudeWatch.API.Router do
  @moduledoc """
  Localhost-only JSON API the Claude Code hook relay POSTs to. Bound to 127.0.0.1
  by Bandit (see `ClaudeWatch.Application`). An optional shared-secret header
  (`X-Claude-Watch-Secret`) guards `/claude/event` against other local processes.

    POST /claude/event  -> {"kind","message","project","cwd","session_id","agent_type","ts"}
    GET  /health        -> {"ok": true}
  """

  use Plug.Router

  alias ClaudeWatch.Notifier

  plug(:match)
  plug(:check_secret)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason, pass: ["application/json"])
  plug(:dispatch)

  @kinds ~w(done permission subagent)

  get "/health" do
    send_json(conn, 200, %{ok: true})
  end

  post "/claude/event" do
    case validate(conn.body_params) do
      {:ok, event} ->
        # Hand off and return immediately — the hook is fire-and-forget.
        Notifier.event(event)
        send_json(conn, 200, %{ok: true})

      {:error, reason} ->
        send_json(conn, 422, %{error: reason})
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not found"})
  end

  # `kind` is required; everything else is best-effort (the formatter tolerates
  # missing fields). session_id defaults so debounce always has a key.
  defp validate(%{"kind" => kind} = p) when kind in @kinds do
    {:ok,
     %{
       kind: kind,
       message: str(p["message"]),
       project: str(p["project"]),
       tab: str(p["tab"]),
       cwd: str(p["cwd"]),
       session_id: str(p["session_id"]) || "unknown",
       agent_type: str(p["agent_type"]),
       ts: p["ts"]
     }}
  end

  defp validate(%{"kind" => k}), do: {:error, "unknown kind: #{inspect(k)}"}
  defp validate(_), do: {:error, "missing kind"}

  defp str(s) when is_binary(s) and s != "", do: s
  defp str(_), do: nil

  # Guard only the event route; /health stays open. Skipped entirely when no
  # secret is configured (the default).
  defp check_secret(%Plug.Conn{request_path: "/claude/event"} = conn, _opts) do
    case Application.get_env(:claude_watch, :shared_secret) do
      secret when secret in [nil, ""] ->
        conn

      expected ->
        given = conn |> get_req_header("x-claude-watch-secret") |> List.first()

        if is_binary(given) and Plug.Crypto.secure_compare(given, expected) do
          conn
        else
          conn |> send_json(401, %{error: "unauthorized"}) |> halt()
        end
    end
  end

  defp check_secret(conn, _opts), do: conn

  defp send_json(conn, code, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(code, Jason.encode!(body))
  end
end
