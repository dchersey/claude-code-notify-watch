# clip-append

Press a hotkey → the current clipboard is reformatted into clean, organized
Markdown by a **local LLM** (qwen on an [Ollama](https://ollama.com) box) and
written into a [NotePlan](https://noteplan.co) note under a timestamp header.
By default it appends to **one note per day**, titled `MM-DD-YY`, in the
`Claude Code` folder — created on the day's first capture. It writes *through*
NotePlan (see [Write-through](#write-through-not-a-file-append)); a plain-file
target still works too.

```
Option+Shift+V (Karabiner) ──touch──▶ ~/.cache/clip-append/trigger
        └─▶ launchd WatchPaths ──▶ /bin/bash ~/bin/clip-append
                └─▶ pbpaste ─▶ qwen via Ollama (format to Markdown)
                          └─▶ NotePlan x-callback addText (create-or-append):

                    # 08-21-26                 ← note title (day's first capture)

                    ---
                    2026-08-21 09:44:02
                    ## Title Qwen Chose
                    ### Section…
```

Each entry is **fully collapsible in NotePlan**: exactly one `##` title per
capture with every other heading demoted to `###`+ (enforced by a deterministic
post-pass — the model is *asked* for that shape, but a normalizer guarantees
it), so a long scratchpad folds into a list of one-line titles for easy
review-and-trim.

## Write-through, not a file append

clip-append does **not** write the note file directly. NotePlan keeps notes it
has loaded in memory and **overwrites external edits** to that file on its next
save/sync — so a raw `>>` append races NotePlan and can be silently clobbered a
second or two later (exactly what began happening after a reboot left NotePlan
holding the note). Instead the worker hands the text to NotePlan via the
`addText` x-callback URL:

```
noteplan://x-callback-url/addText?fileName=<folder/note.txt>&mode=append&text=<…>
```

NotePlan is then the *sole* writer: `addText` **creates** the note when its file
is missing and **appends** when it exists, so there is no external-write conflict
and nothing to clobber.

**One more wrinkle — the open editor.** If the target note is open in NotePlan's
*foreground* editor, a background `addText` with `openNote=no` writes the file but
the editor keeps a stale buffer and saves over the append ~1s later (the capture
is silently lost). So the worker passes **`openNote=yes`**, which makes NotePlan
*reload* the note as it appends, keeping the editor in sync. This also focuses the
note — a handy confirmation the capture landed. Set `CLIP_APPEND_OPEN_NOTE=no` if
you'd rather it stay a silent background append (safe as long as the note isn't
open in the foreground).

URL length is the remaining caveat: a capture of a few thousand characters is
fine (tested well past 7 KB of body, unicode and all); an extreme raw paste could
in principle exceed the URL limit — but the raw text is always saved to
`last-raw.txt` regardless.

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
| `clip-append` | The worker: pbpaste → qwen (raw fallback) → NotePlan write-through. |
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
| `CLIP_APPEND_FOLDER` | `Claude Code` | NotePlan folder for the daily note. |
| `CLIP_APPEND_TITLE` | today, `MM-DD-YY` | Note title/filename (one note per day by default). |
| `CLIP_APPEND_NP_ROOT` | NotePlan's `Notes` container dir | Root that `fileName` is relative to. |
| `CLIP_APPEND_OPEN_NOTE` | `yes` | Reload the note on append so an open editor can't clobber it; `no` skips the reload (no focus change). |
| `CLIP_APPEND_TARGET` | *(unset)* | Legacy absolute-path override (see below). |
| `OLLAMA_REMOTE` | `http://athena.local:11434` | Ollama endpoint. |
| `CLIP_APPEND_MODEL` | `qwen3.6:35b-a3b` | Model for the formatting pass. |

Per-capture target override, no config needed — the trigger file's first line
(or the CLI arg) sets the target for that capture. A path **inside** NotePlan's
notes tree (relative, or absolute under `CLIP_APPEND_NP_ROOT`) is written through
NotePlan; an absolute path **outside** it is appended to as a plain file:

```sh
echo "Meetings/Standup.txt" > ~/.cache/clip-append/trigger   # NotePlan note: fires + redirects
echo /tmp/scratch.md        > ~/.cache/clip-append/trigger   # plain file: direct append
```

Or run directly: `clip-append "Meetings/Standup.txt"`.

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
3. Write path: entries go in via NotePlan's `addText` x-callback, so NotePlan
   renders them itself — no external-change lag and no clobber. If a capture is
   missing, check the log for its `-> NotePlan:<file>` target line; a `[raw]`
   tag just means the model pass fell back but the text still went in.

## Related

- [claude-effort-borders](https://github.com/dchersey/zellij/tree/integration/contrib/claude-effort-borders)
  (in our zellij fork's `contrib/`) — colors each zellij pane frame by the
  Claude Code session's effort level / model, via the fork's
  `set-pane-color --frame` (upstream PR
  [zellij-org/zellij#5303](https://github.com/zellij-org/zellij/pull/5303)).
  Same spirit as this tool — ambient Claude-session awareness — but it lives
  with the zellij fork because it depends on that fork's action.
