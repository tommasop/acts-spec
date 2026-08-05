---
description: Load ACTS v2 durable context pack for a change before writing code
agent: build
---

Load the ACTS v2 scoped context pack for change `$ARGUMENTS` (or the current branch's change if no ID is given).

Run `acts context $ARGUMENTS`. If that fails, run `acts stack status` to list changes, then retry with the correct change ID.

Then summarize for the user:
- Acceptance criteria (the contract you must satisfy)
- Parent chain (what came before this change)
- Verification status
- Checkpoint (where the previous session stopped)
- Session notes and changed files

Do not start writing code until the context pack is loaded and understood.
