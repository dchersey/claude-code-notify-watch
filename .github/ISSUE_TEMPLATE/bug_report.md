---
name: Bug report
about: Something isn't working — no notification, wrong content, or relay errors
title: ''
labels: bug
assignees: ''
---

**What happened**
A clear description of the problem.

**Expected**
What you expected instead.

**Steps to reproduce**
1. …
2. …

**Environment**
- macOS version:
- Elixir version (`elixir --version`):
- Terminal (Apple Terminal / iTerm / Kitty / Ghostty / …):
- Inside zellij? (version, if so):
- Delivery backend (`pushover` / `ntfy` / `bark` / `log`):
- Relay health (`curl -s 127.0.0.1:4747/health`):

**Logs**
Relevant lines from `~/Library/Logs/claude-watch.log` (and, if a hook didn't fire
at all, the `claude --debug` output around the event):

```
(paste here)
```
