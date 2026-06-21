#!/bin/bash
# claude-code-notify-watch — one-shot installer.
#
#   curl -fsSL https://raw.githubusercontent.com/dchersey/claude-code-notify-watch/main/install.sh | bash
#
# Clones/updates the repo, builds the Elixir relay, installs the Claude Code hook
# + the macOS LaunchAgent, and merges the hooks into ~/.claude/settings.json.
# Delivery defaults to "log" (no push) until you add Pushover/ntfy creds — see
# the printed next steps. macOS only (LaunchAgent + Keychain).
set -euo pipefail

REPO_URL="${CLAUDE_WATCH_REPO_URL:-https://github.com/dchersey/claude-code-notify-watch.git}"
DIR="${CLAUDE_WATCH_DIR:-$HOME/.local/share/claude-code-notify-watch}"
BIN="${CLAUDE_WATCH_BIN:-$HOME/.local/bin}"
HOOK="$BIN/claude-watch-notify"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

say() { printf '\033[1m%s\033[0m\n' "$*"; }

# --- prerequisites ---------------------------------------------------------
[ "$(uname)" = "Darwin" ] || echo "WARN: built + tested on macOS (LaunchAgent + Keychain); other OSes are unsupported."
missing=0
for t in git jq curl; do command -v "$t" >/dev/null 2>&1 || { echo "ERROR: missing '$t'"; missing=1; }; done
command -v mix >/dev/null 2>&1 || { echo "ERROR: missing 'mix' (install Elixir: brew install elixir)"; missing=1; }
[ "$missing" = 0 ] || { echo "Install the missing tool(s) and re-run."; exit 1; }

# --- clone or update -------------------------------------------------------
if [ -d "$DIR/.git" ]; then
  say "Updating $DIR"
  git -C "$DIR" pull --ff-only
else
  say "Cloning into $DIR"
  mkdir -p "$(dirname "$DIR")"
  git clone --depth 1 "$REPO_URL" "$DIR"
fi

# --- build -----------------------------------------------------------------
say "Building the relay"
( cd "$DIR" && mix deps.get && mix compile )

# --- hook client -----------------------------------------------------------
say "Installing the hook client -> $HOOK"
mkdir -p "$BIN"
cp "$DIR/bin/claude-watch-notify" "$HOOK"
chmod +x "$HOOK"

# --- merge Claude Code hooks (non-destructive) -----------------------------
say "Wiring Claude Code hooks in $SETTINGS"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
[ -f "$SETTINGS.bak" ] || cp "$SETTINGS" "$SETTINGS.bak"   # keep the original
tmp="$(mktemp)"
jq --arg cmd "$HOOK" '.hooks = ((.hooks // {}) * {
  "Notification": [ { "hooks": [ { "type": "command", "command": $cmd } ] } ],
  "SubagentStop": [ { "hooks": [ { "type": "command", "command": $cmd } ] } ]
})' "$SETTINGS" > "$tmp" && jq -e . "$tmp" >/dev/null && mv "$tmp" "$SETTINGS"

# --- LaunchAgent -----------------------------------------------------------
say "Installing the LaunchAgent"
( cd "$DIR" && ./priv/launchd/install.sh )

cat <<EOF

✅ Installed. Relay: http://127.0.0.1:4747/health   ·   log: ~/Library/Logs/claude-watch.log

Last step — point it at your Apple Watch (default backend only logs):

  1. Install Pushover on your iPhone (pushover.net), create an Application -> API token.
  2. Stash creds in the Keychain (the -w form avoids a trailing newline):
       security add-generic-password -a "\$USER" -s claude-watch-pushover-token -w 'APP_TOKEN'
       security add-generic-password -a "\$USER" -s claude-watch-pushover-user  -w 'USER_KEY'
  3. Set  delivery_backend: "pushover"  in  $DIR/config/config.exs , then:
       (cd "$DIR" && ./priv/launchd/install.sh)

  (Prefer free/self-hosted? Use ntfy or bark instead — see the README.)
EOF
