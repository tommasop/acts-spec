---
description: Install the ponytail minimality skill (rules + slash commands + plugin)
agent: build
---

Install the ponytail minimality skill for `$ARGUMENTS` (or the current project).

Run `acts ponytail install` (or `acts setup --with-ponytail` to wire it at setup time).

Interpret the output:
- Installs `.agents/rules/ponytail.md` (the YAGNI/simplicity ladder), `.opencode/command/ponytail*.md` slash commands (`/ponytail`, `/ponytail-review`, `/ponytail-audit`, …), and the frontmatter plugin.
- `acts review` then appends a ponytail minimality checklist (with per-change diff stats) to the stack's PR body.
- Offline / `curl` missing → the command prints a note and returns; re-run later.