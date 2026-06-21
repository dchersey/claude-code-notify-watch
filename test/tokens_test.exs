defmodule ClaudeWatch.TokensTest do
  use ExUnit.Case, async: false

  alias ClaudeWatch.Tokens

  setup do
    # Each test gets its own JSON file so persistence is observable + isolated.
    path =
      Path.join(
        System.tmp_dir!(),
        "claude-watch-tokens-#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(path) end)
    start_supervised!({Tokens, path: path})
    {:ok, path: path}
  end

  test "put/2 registers a token with its type (the 2-arity call that the router uses)" do
    assert :ok = Tokens.put("abc123", "ios")
    assert Tokens.all() == ["abc123"]
  end

  test "put/1 defaults the type to ios" do
    assert :ok = Tokens.put("def456")
    assert Tokens.all() == ["def456"]
  end

  test "delete/1 removes a token" do
    Tokens.put("keep", "ios")
    Tokens.put("drop", "watch")
    Tokens.delete("drop")
    assert Tokens.all() == ["keep"]
  end

  test "tokens persist to disk and reload", %{path: path} do
    Tokens.put("persisted", "watch")
    assert %{"persisted" => "watch"} = path |> File.read!() |> Jason.decode!()

    # Restart from the same file → tokens survive.
    stop_supervised!(Tokens)
    start_supervised!({Tokens, path: path})
    assert Tokens.all() == ["persisted"]
  end
end
