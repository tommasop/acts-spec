---
description: Render a change's architecture impact as an archify diagram (HTML) and optionally attach it to the PR
agent: build
---

Render the architecture impact of change `$ARGUMENTS` as an archify diagram.

Run `acts diagram $ARGUMENTS` (add `--delta` for a Before/Delta/After comparison, `--attach` to comment on the change's PR).

Interpret the output:
- With the archify renderer installed, `acts diagram` writes `.acts/changes/<id>/archify/*.html` (self-contained interactive HTML).
- If the renderer is missing, the command degrades to a textual delta summary and hints at `acts archify install`.
- For iterative authoring (validate → fix → deliver), use the `acts_archify` tool directly on a candidate IR JSON.