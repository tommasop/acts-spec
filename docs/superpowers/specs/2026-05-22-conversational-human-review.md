# Conversational Human Review for ACTS

## Problem

Current ACTS review (`acts review T1`) opens an interactive terminal TUI via `hunk`.
This works in a TTY but fails in agent-driven workflows where:

1. The agent runs in a non-interactive context (e.g. OpenCode subagent session)
2. The human needs to review per-file via in-chat questions
3. The agent must drive the conversation: render diff, ask "ok?", collect per-file approval

## Solution: `acts gather-review <task-id>`

Add a new subcommand that emits structured JSON to stdout (no TUI).
The agent reads this JSON and drives a conversational review using the `question` tool.

### Subcommand

```
acts gather-review <task-id>
```

Output: single JSON object on stdout (newline-terminated).

### JSON Schema

```jsonc
{
  "task_id": "T1",
  "task_title": "Implement login",
  "rationale": "string | null",         // from task context or actor
  "rejections": [                        // previous rejections
    {
      "approved_by": "user@example.com",
      "created_at": "2026-05-20",
      "comment": "needs tests"           // optional
    }
  ],
  "quality_results": [                   // quality gate results
    {
      "stage": "Test",
      "status": "pass",
      "exit_code": 0,
      "command": "make test",
      "duration_ms": 6993
    }
  ],
  "files": [                             // files changed in task
    {
      "file_path": "src/main.zig",
      "additions": 10,
      "deletions": 2,
      "risk": "low",
      "annotation": "Added login handler",  // optional
      "hunks": [
        {
          "header": "@@ -1,4 +1,10 @@",
          "old_start": 1,
          "new_start": 1,
          "old_count": 4,
          "new_count": 10,
          "lines": " context lines\n+added\n-removed\n"
        }
      ]
    }
  ]
}
```

### Agent Workflow

1. Run `acts gather-review T1`
2. Parse JSON output
3. Present each file to human:
   - Show file_path, risk, additions/deletions, annotation
   - Show hunk diff lines
   - Use `question` tool: "Approve this file?"
4. Collect per-file decisions
5. If all approved, run: `acts gate add --task T1 --type task-review --status approved`
6. If changes requested, run: `acts reject T1 --reason "..."`

### Implementation

- New function `gatherReview()` in `review.zig` (already implemented)
- Called from `main.zig` via `handleGatherReview()` (already implemented)
- JSON escaping uses `db.Database.escapeJsonString` for all string values
- No interactive prompts, no TUI dependencies

### Why not use `acts review` non-interactively?

`acts review` uses `hunk` (interactive diff browser). It requires a TTY.
`gather-review` is designed purely for machine consumption — the agent
reads JSON and drives the interaction via chat tools.

### Future

- Could add `--format markdown` for human-readable preview
- Could add `--output file.json` to write to file
- Could be extended for batch review (multiple tasks)
