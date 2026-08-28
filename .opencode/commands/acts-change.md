---
description: Create a new ACTS v2 change (a checkpoint) on the stack's feature branch
agent: build
---

Create a new ACTS v2 change — a checkpoint (a commit range) on the stack's feature branch.

Usage: `/acts-change add <id> -t "<title>" --accept "<criteria>"`

Run `acts change add $ARGUMENTS`. If that fails, run `acts stack status` first to confirm an active stack exists.

After creating the change, load its context pack with `acts context <id>` before starting implementation.
