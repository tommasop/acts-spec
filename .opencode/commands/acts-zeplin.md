---
description: Extract an API contract from a Zeplin flow/scenario link for analysis and planning
agent: build
---

Extract an API contract from a Zeplin design link for analysis and planning.

Usage: `/acts-zeplin <zeplin-url>`

The URL can be:
- A flow board: `https://app.zeplin.io/project/<id>/flow/<board>`
- A scenario: `https://app.zeplin.io/project/<id>?seid=<section>` or `https://zpl.io/<short>`

Run: `node acts-zeplin-contract.mjs --flow "<url>"` for flow boards, or `--scenario "<url>"` for scenarios. Add `--notes` to include screen notes/annotations.

Requires `ZEPLIN_ACCESS_TOKEN` (env or opencode.json `mcp.zeplin.environment`).

Then synthesize the output into the ACTS planning context:
- Feed the inferred **endpoints + fields** into the change's `--accept` acceptance criteria
- Use the **flow path** to sequence changes (each screen group → one change in the stack)
- Flag non-API screens (onboarding, marketing) as out of scope
