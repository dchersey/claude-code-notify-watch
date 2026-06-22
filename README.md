# claude-code-notify-watch

[![CI](https://github.com/dchersey/claude-code-notify-watch/actions/workflows/ci.yml/badge.svg)](https://github.com/dchersey/claude-code-notify-watch/actions/workflows/ci.yml)
[![License: Source Available](https://img.shields.io/badge/license-Source%20Available%20(MIT%20%2B%20Commons%20Clause)-blue.svg)](LICENSE)

Get a notification **on your Apple Watch** when Claude Code finishes, needs your
permission, or a subagent completes — from any terminal.

Claude Code's built-in cue is terminal-dependent (Kitty raises a macOS
notification; Apple Terminal just bounces the dock) and doesn't reliably reach
your wrist. This captures the signal via Claude Code **hooks** and pushes it
through a service that has an Apple Watch app (Pushover by default; ntfy/Bark
also supported).

```
Claude Code ──hook──▶ ~/.local/bin/claude-watch-notify ──POST 127.0.0.1:4747──▶
   claude-watch (Elixir LaunchAgent): debounce ▶ delivery adapter ──▶ Pushover/ntfy ──▶ iPhone + Watch
```

The hook is **fire-and-forget** (always exits instantly, never stalls Claude),
and the relay **debounces** so a burst of events — or many concurrent sessions —
won't spam your wrist.

## Install (macOS)

```sh
curl -fsSL https://raw.githubusercontent.com/dchersey/claude-code-notify-watch/main/install.sh | bash
```

This clones the repo to `~/.local/share/claude-code-notify-watch`, builds the
relay, installs the hook + a per-user LaunchAgent, and adds the hooks to
`~/.claude/settings.json` (backed up to `settings.json.bak`). It does **not** push
to your watch yet — finish the one step below.

Requirements: macOS, [Elixir](https://elixir-lang.org) (`brew install elixir`),
`jq`, `git`, `curl`.

### Point it at your watch

The default delivery backend is `log` (it just logs), so install is credential-free.
To buzz the watch, pick one — **Pushover** recommended (it has a native Apple Watch app;
ntfy/Bark reach the watch via iPhone notification mirroring):

```sh
# 1. Install Pushover on your iPhone (pushover.net); create an Application -> API token.
# 2. Stash creds in the Keychain (-w avoids a trailing newline that would 401):
security add-generic-password -a "$USER" -s claude-watch-pushover-token -w 'APP_TOKEN'
security add-generic-password -a "$USER" -s claude-watch-pushover-user  -w 'USER_KEY'
# 3. Set  delivery_backend: "pushover"  in config/config.exs, then reinstall:
cd ~/.local/share/claude-code-notify-watch && ./priv/launchd/install.sh
```

ntfy (free/self-hostable) and Bark are drop-in alternatives — set
`delivery_backend: "ntfy"` (or `"bark"`) and stash `claude-watch-ntfy-topic`
(or `claude-watch-bark-key`) in the Keychain.

## What you get

| Claude Code hook | Notification |
|---|---|
| `Notification` / `idle_prompt` | ✅ `<project>` — done |
| `Notification` / `permission_prompt` | 🔐 `<project>` — approve? *(high priority)* |
| `SubagentStop` | 🤖 `<agent>` done — `<project>` |

`<project>` is the basename of the session's cwd, so concurrent sessions are
distinguishable.

### zellij tab name

If the session runs inside [zellij](https://zellij.dev), the **tab name is
appended** — `<project>:<tab>`, e.g. `🔐 zellij:A — approve?`. The hook sends its
`$ZELLIJ_PANE_ID` + session and the **relay** resolves the tab from
`zellij action list-panes --json`, cached per session and refreshed
asynchronously. Keeping that ~2s `list-panes` call off the hook's path means the
hook stays instant (no added notification lag) while the tab is still correct for
a **background** tab (not just whatever's focused) and survives tab renames/moves
(looked up live, not baked in). Outside zellij the suffix is simply omitted. (No
zellij changes required; `tab_name` is already in `list-panes` output.)

### subagent suppression

A turn's last action is often a subagent, so `SubagentStop` tends to fire right
before the `done`. A subagent ping is **suppressed when a `done` for the same
session follows within `subagent_suppress_window_ms` (8s)** — so a subagent only
buzzes when it finishes mid-job while Claude keeps working.

## Tuning

In `config/config.exs` (then `./priv/launchd/install.sh` to reload):

- `done_window_ms` (8s), `permission_window_ms` (1.5s) — debounce/coalesce windows.
- `subagent_suppress_window_ms` (8s) — how long a subagent waits to see if a `done` follows.
- `delivery_backend` — `"pushover"` | `"ntfy"` | `"bark"` | `"log"`.
- `shared_secret` / `CLAUDE_WATCH_SECRET` — optional `X-Claude-Watch-Secret` header on `POST /claude/event` (the listener is already localhost-only).

## How it works

- **Capture** — `~/.claude/settings.json` hooks (`Notification` + `SubagentStop`)
  run `claude-watch-notify`, which maps the event to `{kind, project, pane_id, …}`
  and POSTs it to the relay, fully detached (and instant — no zellij call).
- **Relay** — an Elixir/OTP app (Bandit on `127.0.0.1:4747`): a `Notifier`
  GenServer debounces per session, then a pluggable `Delivery` backend pushes.
  Credentials come from the macOS Keychain (or env), always trimmed.
- **Service** — a per-user LaunchAgent (`org.hersey.claude-watch`), started at
  login, logging to `~/Library/Logs/claude-watch.log`.

## Manual install / uninstall

```sh
git clone https://github.com/dchersey/claude-code-notify-watch.git
cd claude-code-notify-watch && mix deps.get && mix compile
cp bin/claude-watch-notify ~/.local/bin/ && chmod +x ~/.local/bin/claude-watch-notify
# add the two hooks to ~/.claude/settings.json (see install.sh for the jq merge)
./priv/launchd/install.sh                 # load the service
./priv/launchd/install.sh uninstall       # stop + remove it
```

## Why this license?

Claude Code Notify Watch is free to use, modify, and share for any **noncommercial** purpose —
personal use, hobby projects, tinkering, learning, and contributions back are all
welcome and always will be. The one thing the license doesn't permit is **selling**
the software (or charging for hosting/support whose value comes mainly from it).

I built this to solve my own problem and I'm happy to share it freely; I just don't
want it repackaged and sold out from under the people it's meant to help. If you
have a commercial use in mind, get in touch and we can sort something out.

## License

Source-available under the **MIT License with the Commons Clause** — free to use, modify, and redistribute for any **noncommercial** purpose; you may not sell the software. See [LICENSE](LICENSE).
