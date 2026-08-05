---
description: Run the ACTS v2 verification gate for a change (quality gates, records evidence)
agent: build
---

Run the ACTS v2 verification gate for change `$ARGUMENTS` (or the current branch's change if no ID is given).

Run `acts verify $ARGUMENTS`.

Interpret the output:
- Each stage (test/lint/typecheck/build) prints PASS/FAIL with the command and duration.
- If any stage FAILs, fix the failures first — a change MUST NOT be submitted for review until `acts verify` passes.
- If verify passed, you may proceed to `acts review`.
