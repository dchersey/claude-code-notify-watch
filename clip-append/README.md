# clip-append

Press a hotkey → the current clipboard is reformatted into clean, organized
Markdown by a **local LLM** (qwen on an [Ollama](https://ollama.com) box) and
appended to a notes file with a timestamp header. Built for capturing snippets
of Claude Code conversations into a [NotePlan](https://noteplan.co) note, but
the target is any text file.

```
Option+Shift+V (Karabiner) ──touch──▶ ~/.cache/clip-append/trigger
        └─▶ launchd WatchPaths ──▶ /bin/bash ~/bin/clip-append
                └─▶ pbpaste ─▶ qwen via Ollama (format to Markdown) ─▶ append:

                    ---
                    2026-08-12 09:44:02
                    ## Title Qwen Chose
                    ### Section…
```

Each entry is **fully collapsible in NotePlan**: exactly one `##` title per
capture with every other heading demoted to `###`+ (enforced by a deterministic
post-pass — the model is *asked* for that shape, but a normalizer guarantees
it), so a long scratchpad folds into a list of one-line titles for easy
review-and-trim.

## Reliability properties

- **A capture is never lost to formatting.** The raw clipboard is saved to
  `~/.cache/clip-append/last-raw.txt` before the model is consulted, and any
  failure — Ollama unreachable, content too large for the context window,
  model error — falls back to appending the raw text. The log
  (`~/.cache/clip-append/append.log`) tags every entry `[qwen (Ns)]` or `[raw]`.
- **Debounced**: launchd can fire twice for one trigger write (create+write
  vnode events); identical clipboard within 5s is skipped.
- **UTF-8 safe under launchd**: launchd jobs run with no locale, which makes
  `pbpaste` mangle em-dashes/arrows to `?`; the script forces `LANG`.
- **launchd throttles** WatchPaths jobs ~10s apart — two captures inside 10s
  coalesce. Fine for note-taking; don't expect rapid fire.

## Files

| File | What it is |
|------|------------|
| `clip-append` | The worker: pbpaste → qwen (with raw fallback) → append. |
| `co.hersey.clip-append.plist` | launchd agent: WatchPaths on the trigger file. |
| `karabiner-rule.json` | Karabiner-Elements complex-modification rule for Option+Shift+V. |

## Install

```sh
# 1. Worker onto your PATH (the plist invokes it from ~/bin)
cp clip-append ~/bin/ && chmod +x ~/bin/clip-append
mkdir -p ~/.cache/clip-append && touch ~/.cache/clip-append/trigger

# 2. launchd listener
cp co.hersey.clip-append.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/co.hersey.clip-append.plist

# 3. Karabiner hotkey: splice karabiner-rule.json into
#    ~/.config/karabiner/karabiner.json under
#    .profiles[].complex_modifications.rules, e.g.:
jq --slurpfile r karabiner-rule.json \
   '.profiles[0].complex_modifications.rules += $r' \
   ~/.config/karabiner/karabiner.json > /tmp/k.json && cp /tmp/k.json ~/.config/karabiner/karabiner.json
```

The plist runs the worker under **Apple-signed `/bin/bash`** deliberately: the
NotePlan container path is TCC-protected, and a launchd job interpreted by
Homebrew bash is cdhash-bound — it would re-prompt for access after every
`brew upgrade bash`. `/bin/bash`'s grant survives updates.

## Configuration

Environment (set in the plist's `EnvironmentVariables` dict, or export before a
CLI run):

| Var | Default | Meaning |
|-----|---------|---------|
| `CLIP_APPEND_TARGET` | the NotePlan Trading scratchpad | Default notes file to append to. |
| `OLLAMA_REMOTE` | `http://athena.local:11434` | Ollama endpoint. |
| `CLIP_APPEND_MODEL` | `qwen3.6:35b-a3b` | Model for the formatting pass. |

Per-capture target override, no config needed — the trigger file's first line,
if an absolute path, becomes the target for that capture:

```sh
echo /path/to/other-note.txt > ~/.cache/clip-append/trigger   # fires AND redirects
```

Or run directly: `clip-append /path/to/other-note.txt`.

Note the model's context budget: content over ~40k chars skips the model and
appends raw (the formatting request + response must fit the serving window —
32k tokens on our box).

## Entry format

```markdown
---
2026-08-12 09:44:02
## Title The Model Chose

### First Section
…
```

- The `##` title is the collapse handle; NotePlan folds the whole entry to one
  line. (A collapsed fold runs to the *next* heading, so the following entry's
  `---` + timestamp fold into it — the next `##` title is what stays visible.
  Inherent to Markdown folding, not a bug.)
- The blank line before `---` in the appended block is structural: without it,
  Markdown reads the rule as a setext-heading underline for the last line of
  the previous entry.

## Troubleshooting

Triage order when a capture doesn't appear:

1. `tail ~/.cache/clip-append/append.log` — did the worker run? (`[raw]` means
   the model path failed; the text still landed.)
2. `stat -f %Sm ~/.cache/clip-append/trigger` — did Karabiner fire? If not:
   check Secure Input (a focused password field steals keys from Karabiner),
   then whether Karabiner's virtual keyboard driver is running — after a
   Karabiner self-update the driver extension needs re-approval in System
   Settings and keeps ALL rules dead until approved.
3. NotePlan lag: the file append is instant; NotePlan can take seconds to
   notice an external change. Trust the log, not the window.

## Related

- [claude-effort-borders](https://github.com/dchersey/zellij/tree/integration/contrib/claude-effort-borders)
  (in our zellij fork's `contrib/`) — colors each zellij pane frame by the
  Claude Code session's effort level / model, via the fork's
  `set-pane-color --frame` (upstream PR
  [zellij-org/zellij#5303](https://github.com/zellij-org/zellij/pull/5303)).
  Same spirit as this tool — ambient Claude-session awareness — but it lives
  with the zellij fork because it depends on that fork's action.
