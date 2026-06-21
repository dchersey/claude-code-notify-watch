defmodule ClaudeWatch.Tokens do
  @moduledoc """
  APNs device tokens registered by the Claude Code app (`POST /register`).
  Persisted to a small JSON file so the relay keeps them across restarts — mirrors
  the JSON-persistence pattern of `LgaPredictor.CreditLedger`.

  Stored as `%{token => device_type}`.
  """
  use GenServer
  require Logger

  @default_path Path.join([
                  System.user_home() || ".",
                  "Library",
                  "Application Support",
                  "claude-watch",
                  "tokens.json"
                ])

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Register (upsert) a device token."
  def put(token, type \\ "ios") when is_binary(token),
    do: GenServer.call(__MODULE__, {:put, token, type})

  @doc "Remove a device token (e.g. APNs reported it bad/unregistered)."
  def delete(token) when is_binary(token),
    do: GenServer.call(__MODULE__, {:delete, token})

  @doc "All registered tokens, as a list of strings."
  def all, do: GenServer.call(__MODULE__, :all)

  # --- Server ---

  @impl true
  def init(opts) do
    path =
      Keyword.get(opts, :path) ||
        Application.get_env(:claude_watch, :tokens_path) ||
        @default_path

    tokens = load(path)
    Logger.info("[tokens] loaded #{map_size(tokens)} device token(s) from #{path}")
    {:ok, %{path: path, tokens: tokens}}
  end

  @impl true
  def handle_call({:put, token, type}, _from, state) do
    state = %{state | tokens: Map.put(state.tokens, token, type)}
    persist(state)
    {:reply, :ok, state}
  end

  def handle_call({:delete, token}, _from, state) do
    state = %{state | tokens: Map.delete(state.tokens, token)}
    persist(state)
    {:reply, :ok, state}
  end

  def handle_call(:all, _from, state), do: {:reply, Map.keys(state.tokens), state}

  defp load(path) do
    with {:ok, body} <- File.read(path),
         {:ok, map} when is_map(map) <- Jason.decode(body) do
      map
    else
      _ -> %{}
    end
  end

  defp persist(%{path: path, tokens: tokens}) do
    File.mkdir_p(Path.dirname(path))
    File.write(path, Jason.encode!(tokens))
  end
end
