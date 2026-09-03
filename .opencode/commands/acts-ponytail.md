---
description: Install the ponytail minimality skill (rules + slash commands + plugin)
agent: build
---

Install the ponytail minimality skill for `$ARGUMENTS` (or the current project).

Run `acts ponytail install` (or `acts setup --with-ponytail` to wire it at setup time).

Interpret the output:
- Installs `.agents/rules/ponytail.md` (the YAGNI/simplicity ladder), `.opencode/command/ponytail*.md` slash commands (`/ponytail`, `/ponytail-review`, `/ponytail-audit`, …), and the frontmatter plugin.
- Also writes the acts-spec runtime plugin `ponytail-rules.js` (embedded; offline-safe) and registers it in `opencode.json`. Each run it resolves the current project's `AGENTS.md` (CLAUDE.md fallback) and appends a binding precedence directive + path to the system prompt, so the project's rules win over the lazy ladder. Disable with `PONYTAIL_DEFAULT_MODE=off`.
- `acts review` then appends a ponytail minimality checklist (with per-change diff stats) to the stack's PR body.
- Offline / `curl` missing → the rules/commands fetch is skipped, but the embedded runtime plugin is still installed; re-run later.