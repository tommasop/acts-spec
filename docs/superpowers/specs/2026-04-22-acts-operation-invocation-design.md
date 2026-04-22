# ACTS Operation Invocation Mechanism Design

## Overview

A language-agnostic, CLI-based invocation system for ACTS operations with synchronous execution, stdin/stdout JSON communication, and support for launching external tools.

## Core Components

### 1. CLI Tool: `acts`

A command-line tool that serves as the entry point for all ACTS operations.

```bash
# Basic usage
acts run <operation_id> [flags]

# Examples
acts run task-review --task-id T1
acts run story-init --story-id PROJ-42 --title "New Feature"
acts run preflight --task-id T1 --developer "alice"
```

**Global Flags:**
- `--parent-operation <id>`: ID of calling operation (for nested calls)
- `--dry-run`: Show what would be executed without running
- `--verbose`: Show detailed execution logs

**Communication:**
- Input: JSON via stdin
- Output: JSON via stdout
- Logs: stderr
- Exit code: operation status

### 2. Input/Output Contract

Operations receive inputs via **stdin** and write outputs to **stdout**. All communication is JSON.

**Input Schema** (sent to stdin by CLI):
```json
{
  "operation_id": "task-review",
  "timestamp": "2026-04-22T10:30:00Z",
  "caller": "task-start",
  "inputs": {
    "task_id": "T1",
    "developer": "alice"
  },
  "context": {
    "story_id": "PROJ-42",
    "state_path": ".story/state.json",
    "working_dir": "/home/user/project"
  }
}
```

**Output Schema** (written to stdout by operation):
```json
{
  "operation_id": "task-review",
  "status": "success|error|changes_requested|approved|rejected",
  "timestamp": "2026-04-22T10:35:00Z",
  "results": {
    "review_status": "approved",
    "comments": [],
    "files_reviewed": ["src/main.js", "test/main.test.js"]
  },
  "artifacts": {
    "review_file": ".story/reviews/archive/T1-review.md"
  }
}
```

**Logs** (written to stderr):
```
[2026-04-22T10:30:05Z] INFO: Review started
[2026-04-22T10:30:10Z] INFO: Launching lazygit TUI
[2026-04-22T10:35:00Z] INFO: Review completed
```

### 3. Operation Frontmatter Updates

Add execution metadata to operation frontmatter:

```yaml
---
operation_id: task-review
layer: 3
required: true
triggers: "task completion (implicit)"
context_budget: 15000
execution:
  type: "cli"  # cli, script, docker
  command: "task-review"  # Command name or path
  timeout: 300  # seconds
inputs_schema:
  task_id:
    type: string
    required: true
    validation: "^T\\d+$"
  developer:
    type: string
    required: false
outputs_schema:
  review_status:
    type: string
    enum: ["approved", "changes_requested"]
  review_file:
    type: string
    description: "Path to review artifact"
---
```

### 4. Operation Calling Another Operation

Operations can synchronously call other operations via stdin/stdout:

**CLI invocation with stdin/stdout**
```bash
#!/bin/bash
# Inside task-start operation

# Build input JSON
INPUT=$(cat <<EOF
{
  "operation_id": "task-review",
  "caller": "task-start",
  "inputs": {
    "task_id": "$TASK_ID",
    "developer": "$DEVELOPER"
  },
  "context": {
    "story_id": "$STORY_ID",
    "state_path": ".story/state.json"
  }
}
EOF
)

# Call task-review and capture output
OUTPUT=$(echo "$INPUT" | acts run task-review --parent-operation "task-start")

# Parse the output
REVIEW_STATUS=$(echo "$OUTPUT" | jq -r '.status')

if [ "$REVIEW_STATUS" == "approved" ]; then
  # Continue...
else
  # Handle changes requested...
fi
```

**Using helper library (bash)**
```bash
#!/bin/bash
source .acts/lib/acts-run.sh

# Helper function handles JSON serialization
OUTPUT=$(acts_call "task-review" \
  --input task_id="$TASK_ID" \
  --input developer="$DEVELOPER")

# Check exit code and parse results
if [ $? -eq 0 ]; then
  REVIEW_STATUS=$(echo "$OUTPUT" | jq -r '.results.review_status')
fi
```

**Environment variables (auto-set by CLI)**
```bash
# Set by CLI when invoking operation
export ACTS_OPERATION_ID="task-start"
export ACTS_STORY_ID="PROJ-42"
export ACTS_STATE_PATH=".story/state.json"

# Operation reads inputs from stdin, writes to stdout
```

### 5. External Tool Integration

Operations can launch TUIs and capture results:

```yaml
# In operation frontmatter
external_tools:
  - name: lazygit
    install: "brew install lazygit"
    min_version: "0.40.0"
    capture_output: true
```

**Example: Launching lazygit from task-review**
```bash
#!/bin/bash
# task-review operation implementation

# Read inputs from stdin
INPUT=$(cat)
TASK_ID=$(echo "$INPUT" | jq -r '.inputs.task_id')

# Launch lazygit TUI
# User reviews interactively
lazygit
LAZYGIT_EXIT=$?

# Check if lazygit indicated approval (via exit code or file)
if [ -f ".story/reviews/active/${TASK_ID}-review.md" ]; then
  STATUS="approved"
else
  STATUS="changes_requested"
fi

# Write operation output to stdout
cat <<EOF
{
  "operation_id": "task-review",
  "status": "$STATUS",
  "results": {
    "review_status": "$STATUS",
    "review_file": ".story/reviews/active/${TASK_ID}-review.md"
  },
  "artifacts": {
    "review_file": ".story/reviews/active/${TASK_ID}-review.md"
  }
}
EOF
```

### 6. Directory Structure

```
.acts/
├── acts                    # CLI binary/script
├── operations/
│   ├── task-start.md       # Operation definition (markdown)
│   ├── task-review.md      # Operation definition
│   ├── task-start          # Operation implementation (executable)
│   └── task-review         # Operation implementation
├── schemas/
│   ├── operation-meta.json
│   └── invocation.json     # New: invocation protocol schema
└── lib/
    ├── acts-run.sh         # Shell helper library
    ├── acts-run.py         # Python helper library
    └── acts-run.js         # Node.js helper library
```

**No temporary files needed** - all communication via stdin/stdout.

### 7. Exit Codes

Operations MUST exit with these codes:

| Exit Code | Meaning | Action |
|-----------|---------|--------|
| 0 | Success | Continue caller execution |
| 1 | Generic error | Caller handles error |
| 2 | Changes requested | Return to caller for retry |
| 3 | Rejected | Caller aborts or handles |
| 10 | Precondition failed | Missing inputs, invalid state |
| 11 | Tool not available | External tool missing |
| 20 | Timeout | Operation timed out |

### 8. Implementation Options

**Option A: Bash CLI (Minimal)**
- Single bash script: `acts`
- Parses markdown frontmatter
- Handles input/output JSON
- Calls operation executables

**Option B: Python CLI (Feature-rich)**
- Python package: `acts-cli`
- Validates schemas
- Manages operation lifecycle
- Better error handling

**Option C: Hybrid**
- Core CLI in Python
- Operations can be any language
- Helper libraries for common languages

## Usage Examples

### Example 1: Task Flow

```bash
# 1. Start task (calls preflight internally)
acts run task-start --task-id T1

# 2. Work happens... then complete task
# task-start calls task-review when done
acts run task-start --task-id T1 --action complete

# 3. Review story when all tasks done
acts run story-review
```

### Example 2: Nested Operation Call

```bash
# task-start operation internally:
echo "Running task-review..." >&2

# Build input and call operation
INPUT=$(jq -n \
  --arg task_id "$TASK_ID" \
  --arg developer "$DEVELOPER" \
  '{operation_id: "task-review", inputs: {task_id: $task_id, developer: $developer}}')

OUTPUT=$(echo "$INPUT" | acts run task-review --parent-operation "task-start")

REVIEW_STATUS=$(echo "$OUTPUT" | jq -r '.status')
if [ "$REVIEW_STATUS" != "approved" ]; then
  echo "Review not approved, stopping" >&2
  exit 2
fi
```

### Example 3: With External Tool

```bash
# task-review with lazygit
acts run task-review \
  --task-id T1 \
  --with-tool lazygit

# Output contains review results from TUI session
```

## Benefits

1. **Clear invocation**: `acts run <operation>` is unambiguous
2. **Language agnostic**: Operations can be bash, python, node, etc.
3. **Structured I/O**: JSON via stdin/stdout provides clear contracts
4. **No file I/O**: Cleaner, faster, no temp file management
5. **Synchronous**: Caller waits, gets results immediately
6. **Composable**: Operations can call other operations
7. **Testable**: Can pipe JSON directly to operations for testing
8. **Debuggable**: `--verbose` flag shows full JSON exchange

## Questions for Approval

1. **CLI implementation**: Bash script or Python package?
2. **Operation executables**: Should operations be separate files (`.acts/operations/task-review`) or embedded in markdown?
3. **State management**: Should the CLI auto-update `state.json` or leave that to operations?
4. **External tools**: Should the CLI manage tool installation/version checking?
5. **Naming**: Keep `acts run` or prefer something else?

## Recommendation

Implement **Option C: Hybrid** with:
- Python-based core CLI (`acts` command)
- Operations as standalone executables
- Helper library for bash operations
- Auto-generated TypeScript definitions for Node operations

This gives us the best balance of features and flexibility.
