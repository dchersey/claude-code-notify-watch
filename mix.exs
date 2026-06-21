defmodule ClaudeWatch.MixProject do
  use Mix.Project

  def project do
    [
      app: :claude_watch,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  # Self-contained release option (`MIX_ENV=prod mix release`). The LaunchAgent
  # actually runs from source via priv/launchd/boot.sh, so this is here for parity
  # with noise-defence and future packaging — not required to run.
  defp releases do
    [
      claude_watch: [
        include_executables_for: [:unix],
        applications: [claude_watch: :permanent]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ClaudeWatch.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.5"},
      {:pigeon, "~> 2.0"}
    ]
  end
end
