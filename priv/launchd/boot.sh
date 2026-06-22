#!/bin/bash
# Launch wrapper for the claude-watch LaunchAgent.
#
# Runs this instead of `elixir -S mix run` directly so the service self-heals
# after a toolchain upgrade: a prod build compiled against an old Elixir throws
# `undef` for stdlib protocol impls at runtime and crashes. We detect a changed
# toolchain via a version marker and clean-rebuild before exec'ing the app.
#
# `exec` at the end replaces this shell with the BEAM so launchd tracks the real
# process (KeepAlive works). Apple-signed /bin/bash per the global macOS TCC rule.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$REPO" || exit 1
export MIX_ENV=prod

# Optional local, gitignored overrides (e.g. CLAUDE_WATCH_* env) so a machine can
# configure the relay without editing tracked files or the LaunchAgent plist.
if [ -f "$REPO/.env.local" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$REPO/.env.local"
  set +a
fi

log() { printf '%s [boot] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"; }

sig="$(elixir --version 2>/dev/null | tr -d '\n')"
marker="_build/prod/.toolchain"

if [ -z "$sig" ]; then
  log "elixir not on PATH — running existing build as-is"
elif [ ! -f "$marker" ] || [ "$(cat "$marker" 2>/dev/null)" != "$sig" ]; then
  log "toolchain changed (or first run) → clean prod rebuild for: $sig"
  rm -rf _build/prod
  mix deps.get >/dev/null 2>&1 || true
  if mix compile >/dev/null 2>&1; then
    mkdir -p _build/prod && printf '%s' "$sig" >"$marker"
    log "clean rebuild complete"
  else
    log "WARNING: prod compile failed — starting whatever build exists"
  fi
else
  # Same toolchain: fast incremental compile to pick up any source changes.
  mix compile >/dev/null 2>&1 || log "incremental compile failed (continuing)"
fi

exec elixir -S mix run --no-halt
