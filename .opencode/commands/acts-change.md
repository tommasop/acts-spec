---
description: Create a new ACTS v2 change (stacked branch) on top of the current stack
agent: build
---

Create a new ACTS v2 change on top of the current stack.

Usage: `/acts-change add <id> -t "<title>" --accept "<criteria>"`

Run `acts change add $ARGUMENTS`. If that fails, run `acts stack status` first to confirm an active stack exists.

After creating the change, load its context pack with `acts context <id>` before starting implementation.
