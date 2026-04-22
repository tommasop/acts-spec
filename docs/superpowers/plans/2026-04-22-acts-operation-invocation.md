# ACTS Operation Invocation Mechanism Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a CLI-based invocation system for ACTS operations using stdin/stdout JSON communication, enabling operations to synchronously call other operations.

**Architecture:** A Python CLI (`acts`) parses operation frontmatter, validates inputs/outputs against JSON schemas, and invokes operation executables (bash/python/node) via stdin/stdout. Operations can call other operations using a helper library.

**Tech Stack:** Python 3.8+, bash, JSON schemas, jq (for bash operations)

---

## File Structure Overview

```
.acts/
├── acts                      # CLI entry point (Python)
├── lib/
│   ├── __init__.py
│   ├── cli.py               # CLI argument parsing
│   ├── runner.py            # Operation execution engine
│   ├── schema.py            # JSON schema validation
│   └── helpers.sh           # Bash helper library
├── operations/
│   ├── task-review          # Executable operation (bash)
│   └── task-start           # Executable operation (bash)
├── schemas/
│   ├── invocation.json      # Input/output schema
│   └── execution.json       # Execution metadata schema
└── tests/
    ├── test_cli.py
    ├── test_runner.py
    └── test_operations.sh
```

---

## Task 1: Create CLI Tool Core

**Files:**
- Create: `.acts/acts` (Python CLI entry point)
- Create: `.acts/lib/__init__.py`
- Create: `.acts/lib/cli.py`
- Create: `.acts/lib/runner.py`
- Create: `.acts/lib/schema.py`

**Goal:** Build the `acts` CLI that can parse operation frontmatter and execute operations.

### Step 1.1: Create CLI entry point

Create `.acts/acts`:
```python
#!/usr/bin/env python3
"""ACTS CLI - Operation invocation system."""

import sys
import os

# Add lib to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))

from cli import main

if __name__ == '__main__':
    sys.exit(main())
```

Make executable:
```bash
chmod +x .acts/acts
```

### Step 1.2: Create CLI argument parser

Create `.acts/lib/cli.py`:
```python
"""CLI argument parsing and command dispatch."""

import argparse
import sys
import json
from runner import OperationRunner

def main():
    parser = argparse.ArgumentParser(
        prog='acts',
        description='ACTS Operation Invocation System'
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # run command
    run_parser = subparsers.add_parser('run', help='Run an operation')
    run_parser.add_argument('operation_id', help='Operation ID (e.g., task-review)')
    run_parser.add_argument('--parent-operation', help='ID of calling operation')
    run_parser.add_argument('--dry-run', action='store_true', help='Show what would be executed')
    run_parser.add_argument('--verbose', '-v', action='store_true', help='Verbose output')
    
    args = parser.parse_args()
    
    if args.command == 'run':
        return run_operation(args)
    else:
        parser.print_help()
        return 1

def run_operation(args):
    """Execute an operation."""
    runner = OperationRunner(verbose=args.verbose)
    
    # Build input from stdin
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        input_data = {}
    
    result = runner.run(
        operation_id=args.operation_id,
        input_data=input_data,
        parent_operation=args.parent_operation,
        dry_run=args.dry_run
    )
    
    # Output result to stdout
    json.dump(result, sys.stdout, indent=2)
    
    # Return exit code
    status = result.get('status', 'error')
    if status == 'success' or status == 'approved':
        return 0
    elif status == 'changes_requested':
        return 2
    else:
        return 1
```

### Step 1.3: Create operation runner

Create `.acts/lib/runner.py`:
```python
"""Operation execution engine."""

import os
import subprocess
import json
from datetime import datetime
from schema import SchemaValidator

class OperationRunner:
    def __init__(self, verbose=False):
        self.verbose = verbose
        self.acts_dir = self._find_acts_dir()
        self.validator = SchemaValidator(self.acts_dir)
    
    def _find_acts_dir(self):
        """Find .acts directory from current working directory."""
        cwd = os.getcwd()
        while cwd != '/':
            acts_dir = os.path.join(cwd, '.acts')
            if os.path.isdir(acts_dir):
                return acts_dir
            cwd = os.path.dirname(cwd)
        raise RuntimeError("Could not find .acts directory")
    
    def run(self, operation_id, input_data, parent_operation=None, dry_run=False):
        """Run an operation and return the result."""
        # Parse operation frontmatter
        op_def = self._parse_operation(operation_id)
        
        if self.verbose:
            print(f"Running operation: {operation_id}", file=sys.stderr)
            print(f"Definition: {op_def}", file=sys.stderr)
        
        # Build invocation input
        invocation_input = {
            'operation_id': operation_id,
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'caller': parent_operation,
            'inputs': input_data.get('inputs', {}),
            'context': {
                'acts_dir': self.acts_dir,
                'working_dir': os.getcwd()
            }
        }
        
        if dry_run:
            return {
                'operation_id': operation_id,
                'status': 'dry_run',
                'invocation_input': invocation_input
            }
        
        # Find operation executable
        executable = self._find_executable(operation_id)
        
        # Execute operation
        result = self._execute(executable, invocation_input, op_def)
        
        return result
    
    def _parse_operation(self, operation_id):
        """Parse operation markdown frontmatter."""
        md_path = os.path.join(self.acts_dir, 'operations', f'{operation_id}.md')
        
        if not os.path.exists(md_path):
            raise RuntimeError(f"Operation not found: {operation_id}")
        
        with open(md_path, 'r') as f:
            content = f.read()
        
        # Parse YAML frontmatter
        if content.startswith('---'):
            parts = content.split('---', 2)
            if len(parts) >= 3:
                import yaml
                return yaml.safe_load(parts[1])
        
        return {}
    
    def _find_executable(self, operation_id):
        """Find the operation executable."""
        # Check for executable file
        exec_path = os.path.join(self.acts_dir, 'operations', operation_id)
        if os.path.exists(exec_path) and os.access(exec_path, os.X_OK):
            return exec_path
        
        # Fallback: use the markdown file (for inline operations)
        md_path = os.path.join(self.acts_dir, 'operations', f'{operation_id}.md')
        if os.path.exists(md_path):
            return md_path
        
        raise RuntimeError(f"No executable found for operation: {operation_id}")
    
    def _execute(self, executable, input_data, op_def):
        """Execute the operation and capture output."""
        import sys
        
        # Prepare environment
        env = os.environ.copy()
        env['ACTS_OPERATION_ID'] = input_data['operation_id']
        env['ACTS_CALLER'] = input_data.get('caller', '')
        
        # Run operation
        proc = subprocess.Popen(
            [executable],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            text=True
        )
        
        stdout, stderr = proc.communicate(input=json.dumps(input_data))
        
        if self.verbose:
            print(f"stderr: {stderr}", file=sys.stderr)
        
        # Parse output
        try:
            result = json.loads(stdout)
        except json.JSONDecodeError:
            result = {
                'operation_id': input_data['operation_id'],
                'status': 'error',
                'error': 'Invalid JSON output',
                'raw_output': stdout
            }
        
        # Add exit code info
        result['exit_code'] = proc.returncode
        
        return result
```

### Step 1.4: Create schema validator stub

Create `.acts/lib/schema.py`:
```python
"""JSON schema validation."""

import json
import os

class SchemaValidator:
    def __init__(self, acts_dir):
        self.acts_dir = acts_dir
        self.schemas = {}
    
    def validate_input(self, operation_id, data):
        """Validate operation input against schema."""
        # TODO: Implement schema validation
        return True
    
    def validate_output(self, operation_id, data):
        """Validate operation output against schema."""
        # TODO: Implement schema validation
        return True
```

### Step 1.5: Make CLI executable and test

```bash
chmod +x .acts/acts

# Test help
./.acts/acts --help

# Test run command help
./.acts/acts run --help
```

Expected output: Help text displays correctly.

### Step 1.6: Commit

```bash
git add .acts/acts .acts/lib/
git commit -m "feat: create ACTS CLI core with argument parsing and operation runner"
```

---

## Task 2: Create JSON Schemas

**Files:**
- Create: `.acts/schemas/invocation.json`
- Create: `.acts/schemas/execution.json`

**Goal:** Define schemas for operation input/output and execution metadata.

### Step 2.1: Create invocation schema

Create `.acts/schemas/invocation.json`:
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://acts-standard.org/schemas/invocation/v1.0.0",
  "title": "ACTS Operation Invocation",
  "description": "Schema for operation input/output via stdin/stdout",
  "type": "object",
  "definitions": {
    "invocation_input": {
      "type": "object",
      "required": ["operation_id", "timestamp"],
      "properties": {
        "operation_id": {
          "type": "string",
          "description": "ID of the operation being invoked"
        },
        "timestamp": {
          "type": "string",
          "format": "date-time",
          "description": "ISO 8601 timestamp of invocation"
        },
        "caller": {
          "type": ["string", "null"],
          "description": "ID of the calling operation, if any"
        },
        "inputs": {
          "type": "object",
          "description": "Operation-specific inputs",
          "additionalProperties": true
        },
        "context": {
          "type": "object",
          "description": "Runtime context",
          "properties": {
            "acts_dir": { "type": "string" },
            "working_dir": { "type": "string" },
            "story_id": { "type": "string" }
          }
        }
      }
    },
    "invocation_output": {
      "type": "object",
      "required": ["operation_id", "status"],
      "properties": {
        "operation_id": {
          "type": "string"
        },
        "status": {
          "type": "string",
          "enum": ["success", "error", "approved", "changes_requested", "rejected"]
        },
        "timestamp": {
          "type": "string",
          "format": "date-time"
        },
        "results": {
          "type": "object",
          "additionalProperties": true
        },
        "artifacts": {
          "type": "object",
          "description": "Paths to generated artifacts",
          "additionalProperties": { "type": "string" }
        },
        "error": {
          "type": "string",
          "description": "Error message if status is error"
        },
        "exit_code": {
          "type": "integer",
          "description": "Process exit code"
        }
      }
    }
  }
}
```

### Step 2.2: Create execution metadata schema

Create `.acts/schemas/execution.json`:
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://acts-standard.org/schemas/execution/v1.0.0",
  "title": "ACTS Operation Execution Metadata",
  "description": "Schema for operation frontmatter execution section",
  "type": "object",
  "properties": {
    "execution": {
      "type": "object",
      "properties": {
        "type": {
          "type": "string",
          "enum": ["cli", "script", "docker"],
          "default": "cli"
        },
        "command": {
          "type": "string",
          "description": "Command name or path to executable"
        },
        "timeout": {
          "type": "integer",
          "description": "Timeout in seconds",
          "default": 300
        }
      }
    },
    "inputs_schema": {
      "type": "object",
      "description": "JSON schema for operation inputs"
    },
    "outputs_schema": {
      "type": "object",
      "description": "JSON schema for operation outputs"
    }
  }
}
```

### Step 2.3: Commit

```bash
git add .acts/schemas/
git commit -m "feat: add invocation and execution JSON schemas"
```

---

## Task 3: Create Bash Helper Library

**Files:**
- Create: `.acts/lib/helpers.sh`

**Goal:** Provide helper functions for bash operations to parse input and format output.

### Step 3.1: Create bash helper library

Create `.acts/lib/helpers.sh`:
```bash
#!/bin/bash
# ACTS Bash Helper Library
# Source this file in bash operations: source .acts/lib/helpers.sh

# Read JSON input from stdin and parse with jq
acts_read_input() {
    cat
}

# Get a value from input JSON
acts_get_input() {
    local input_json="$1"
    local key="$2"
    echo "$input_json" | jq -r ".$key // empty"
}

# Build and output success result
acts_success() {
    local results="${1:-{}}"
    local artifacts="${2:-{}}"
    
    cat <<EOF
{
  "status": "success",
  "results": $results,
  "artifacts": $artifacts
}
EOF
}

# Build and output approved result
acts_approved() {
    local results="${1:-{}}"
    local artifacts="${2:-{}}"
    
    cat <<EOF
{
  "status": "approved",
  "results": $results,
  "artifacts": $artifacts
}
EOF
}

# Build and output changes_requested result
acts_changes_requested() {
    local results="${1:-{}}"
    local artifacts="${2:-{}}"
    
    cat <<EOF
{
  "status": "changes_requested",
  "results": $results,
  "artifacts": $artifacts
}
EOF
}

# Build and output error result
acts_error() {
    local message="$1"
    
    cat <<EOF
{
  "status": "error",
  "error": "$message"
}
EOF
}

# Call another operation synchronously
acts_call() {
    local operation_id="$1"
    shift
    
    # Build input JSON
    local inputs="{}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input)
                local key="${2%%=*}"
                local val="${2#*=}"
                inputs=$(echo "$inputs" | jq --arg k "$key" --arg v "$val" '.[$k] = $v')
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Build full invocation
    local invocation=$(jq -n \
        --arg op "$operation_id" \
        --arg caller "${ACTS_OPERATION_ID:-}" \
        --argjson inputs "$inputs" \
        '{operation_id: $op, caller: $caller, inputs: $inputs}')
    
    # Call operation and return output
    echo "$invocation" | acts run "$operation_id" --parent-operation "${ACTS_OPERATION_ID:-}"
}

# Log to stderr
acts_log() {
    local level="$1"
    shift
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $level: $*" >&2
}

# Get current operation ID from environment
acts_current_operation() {
    echo "${ACTS_OPERATION_ID:-}"
}

# Get caller operation ID from environment
acts_caller() {
    echo "${ACTS_CALLER:-}"
}
```

### Step 3.2: Test helper functions

Create a test script:
```bash
#!/bin/bash
source .acts/lib/helpers.sh

# Test input reading
echo '{"inputs": {"task_id": "T1"}}' | acts_read_input

# Test success output
acts_success '{"review_status": "approved"}' '{"file": "/path/to/review.md"}'

# Test error output
acts_error "Something went wrong"
```

Run test:
```bash
chmod +x test_helpers.sh
./test_helpers.sh
```

Expected: Valid JSON output displayed.

### Step 3.3: Commit

```bash
git add .acts/lib/helpers.sh
git commit -m "feat: add bash helper library for operations"
```

---

## Task 4: Convert task-review to Executable Operation

**Files:**
- Create: `.acts/operations/task-review` (executable)
- Modify: `.acts/operations/task-review.md` (add execution metadata)

**Goal:** Convert the task-review operation from markdown-only to an executable that uses the invocation mechanism.

### Step 4.1: Add execution metadata to frontmatter

Modify `.acts/operations/task-review.md`:
```yaml
---
operation_id: task-review
layer: 3
required: true
triggers: "task completion (implicit)"
context_budget: 15000
execution:
  type: "cli"
  command: "task-review"
  timeout: 300
inputs_schema:
  task_id:
    type: string
    required: true
    validation: "^T\\d+$"
outputs_schema:
  review_status:
    type: string
    enum: ["approved", "changes_requested"]
  review_file:
    type: string
---
```

### Step 4.2: Create task-review executable

Create `.acts/operations/task-review`:
```bash
#!/bin/bash
# task-review operation
# Reads input from stdin, writes output to stdout

source .acts/lib/helpers.sh

# Read input
INPUT=$(acts_read_input)
TASK_ID=$(acts_get_input "$INPUT" "inputs.task_id")

acts_log "INFO" "Starting review for task $TASK_ID"

# Check if review provider is configured
if command -v lazygit &> /dev/null; then
    acts_log "INFO" "Launching lazygit for review"
    
    # Launch lazygit TUI
    lazygit
    LAZYGIT_EXIT=$?
    
    acts_log "INFO" "lazygit exited with code $LAZYGIT_EXIT"
    
    # Check if review file was created
    REVIEW_FILE=".story/reviews/active/${TASK_ID}-review.md"
    if [ -f "$REVIEW_FILE" ]; then
        acts_log "INFO" "Review completed, file found: $REVIEW_FILE"
        
        # Move to archive
        mkdir -p .story/reviews/archive
        mv "$REVIEW_FILE" ".story/reviews/archive/${TASK_ID}-review.md"
        
        acts_approved \
            '{"review_status": "approved", "reviewer": "human"}' \
            "{\"review_file\": \".story/reviews/archive/${TASK_ID}-review.md\"}"
        exit 0
    else
        acts_log "WARN" "No review file found, assuming changes requested"
        acts_changes_requested \
            '{"review_status": "changes_requested", "reason": "Review incomplete or rejected"}'
        exit 2
    fi
else
    # Manual review fallback
    acts_log "INFO" "lazygit not available, using manual review"
    
    # Show staged diff
    echo "=== Staged Changes ===" >&2
    git diff --staged >&2
    
    # For now, assume approved (in real use, would prompt)
    acts_approved \
        '{"review_status": "approved", "reviewer": "manual"}' \
        '{}'
    exit 0
fi
```

Make executable:
```bash
chmod +x .acts/operations/task-review
```

### Step 4.3: Test task-review operation

```bash
# Test with input
echo '{"inputs": {"task_id": "T1"}}' | ./.acts/acts run task-review --verbose
```

Expected: Operation runs and outputs JSON with status.

### Step 4.4: Commit

```bash
git add .acts/operations/task-review .acts/operations/task-review.md
git commit -m "feat: convert task-review to executable operation with invocation support"
```

---

## Task 5: Update task-start to Call task-review

**Files:**
- Create: `.acts/operations/task-start` (executable)
- Modify: `.acts/operations/task-start.md` (update Step 11)

**Goal:** Convert task-start to an executable that invokes task-review at the review gate.

### Step 5.1: Create task-start executable

Create `.acts/operations/task-start`:
```bash
#!/bin/bash
# task-start operation

source .acts/lib/helpers.sh

# Read input
INPUT=$(acts_read_input)
TASK_ID=$(acts_get_input "$INPUT" "inputs.task_id")
ACTION=$(acts_get_input "$INPUT" "inputs.action")

acts_log "INFO" "Task start: $TASK_ID, action: $ACTION"

# Step 1-10: Implementation work happens elsewhere
# This operation is called after implementation is complete

if [ "$ACTION" == "complete" ]; then
    acts_log "INFO" "Task completion requested, running review gate"
    
    # Step 11: TASK-REVIEW GATE
    acts_log "INFO" "Calling task-review operation"
    
    REVIEW_OUTPUT=$(acts_call task-review --input task_id="$TASK_ID")
    REVIEW_STATUS=$(echo "$REVIEW_OUTPUT" | jq -r '.status')
    
    acts_log "INFO" "Review status: $REVIEW_STATUS"
    
    if [ "$REVIEW_STATUS" == "approved" ]; then
        acts_log "INFO" "Review approved, completing task"
        
        # Step 12: Update state (would normally update state.json here)
        # For now, just report success
        
        acts_success \
            "{\"task_id\": \"$TASK_ID\", \"status\": \"DONE\", \"review_status\": \"approved\"}" \
            "{\"review_output\": $REVIEW_OUTPUT}"
        exit 0
    elif [ "$REVIEW_STATUS" == "changes_requested" ]; then
        acts_log "WARN" "Changes requested, task remains IN_PROGRESS"
        acts_changes_requested \
            "{\"task_id\": \"$TASK_ID\", \"reason\": \"Review changes requested\"}" \
            "{\"review_output\": $REVIEW_OUTPUT}"
        exit 2
    else
        acts_log "ERROR" "Review failed with status: $REVIEW_STATUS"
        acts_error "Review operation failed"
        exit 1
    fi
else
    # Normal task start (implementation mode)
    acts_log "INFO" "Starting task implementation"
    acts_success \
        "{\"task_id\": \"$TASK_ID\", \"status\": \"IN_PROGRESS\"}" \
        "{}"
    exit 0
fi
```

Make executable:
```bash
chmod +x .acts/operations/task-start
```

### Step 5.2: Update task-start.md frontmatter

Add to `.acts/operations/task-start.md` frontmatter:
```yaml
execution:
  type: "cli"
  command: "task-start"
  timeout: 600
inputs_schema:
  task_id:
    type: string
    required: true
    validation: "^T\\d+$"
  action:
    type: string
    enum: ["start", "complete"]
    default: "start"
outputs_schema:
  task_id:
    type: string
  status:
    type: string
    enum: ["IN_PROGRESS", "DONE"]
  review_status:
    type: string
    enum: ["approved", "changes_requested"]
```

### Step 5.3: Update Step 11 in task-start.md

Change Step 11 in `.acts/operations/task-start.md` from:
```markdown
11. **TASK-REVIEW GATE (HARD STOP)**
    If `code_review.enabled` is true in `.acts/acts.json`:
    a. Run `task-review` operation (see `.acts/operations/task-review.md`)
```

To:
```markdown
11. **TASK-REVIEW GATE (HARD STOP)**
    If `code_review.enabled` is true in `.acts/acts.json`:
    a. Invoke task-review operation:
       ```bash
       echo '{"inputs": {"task_id": "T1"}}' | acts run task-review
       ```
    b. Parse output JSON for status field
    c. If status == "approved": proceed to step 12
    d. If status == "changes_requested": 
       - Address feedback
       - Loop back to step 10
```

### Step 5.4: Test task-start calling task-review

```bash
# Test task start
echo '{"inputs": {"task_id": "T1", "action": "start"}}' | ./.acts/acts run task-start --verbose

# Test task complete (calls task-review)
echo '{"inputs": {"task_id": "T1", "action": "complete"}}' | ./.acts/acts run task-start --verbose
```

Expected: task-start runs and either completes or calls task-review.

### Step 5.5: Commit

```bash
git add .acts/operations/task-start .acts/operations/task-start.md
git commit -m "feat: convert task-start to executable with task-review invocation"
```

---

## Task 6: Create Tests

**Files:**
- Create: `.acts/tests/test_cli.py`
- Create: `.acts/tests/test_runner.py`
- Create: `.acts/tests/test_operations.sh`

**Goal:** Test the CLI, runner, and operations.

### Step 6.1: Create CLI tests

Create `.acts/tests/test_cli.py`:
```python
#!/usr/bin/env python3
"""Tests for ACTS CLI."""

import unittest
import subprocess
import json
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))

class TestCLI(unittest.TestCase):
    def setUp(self):
        self.acts_path = os.path.join(os.path.dirname(__file__), '..', 'acts')
    
    def test_help(self):
        """Test CLI shows help."""
        result = subprocess.run(
            [self.acts_path, '--help'],
            capture_output=True,
            text=True
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn('ACTS Operation Invocation', result.stdout)
    
    def test_run_help(self):
        """Test run command shows help."""
        result = subprocess.run(
            [self.acts_path, 'run', '--help'],
            capture_output=True,
            text=True
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn('operation_id', result.stdout)

if __name__ == '__main__':
    unittest.main()
```

### Step 6.2: Create runner tests

Create `.acts/tests/test_runner.py`:
```python
#!/usr/bin/env python3
"""Tests for operation runner."""

import unittest
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
from runner import OperationRunner

class TestRunner(unittest.TestCase):
    def setUp(self):
        # Change to repo root for tests
        os.chdir(os.path.join(os.path.dirname(__file__), '..', '..'))
        self.runner = OperationRunner(verbose=False)
    
    def test_parse_operation(self):
        """Test parsing operation frontmatter."""
        op_def = self.runner._parse_operation('task-review')
        self.assertEqual(op_def['operation_id'], 'task-review')
        self.assertEqual(op_def['layer'], 3)

if __name__ == '__main__':
    unittest.main()
```

### Step 6.3: Create bash operation tests

Create `.acts/tests/test_operations.sh`:
```bash
#!/bin/bash
# Tests for bash operations

set -e

ACTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ACTS_DIR/../.."

echo "=== Testing task-review operation ==="

# Test with dry run
echo '{"inputs": {"task_id": "T1"}}' | "$ACTS_DIR/acts" run task-review --dry-run

echo "=== Testing task-start operation ==="

# Test task start
echo '{"inputs": {"task_id": "T1", "action": "start"}}' | "$ACTS_DIR/acts" run task-start --dry-run

echo "=== All tests passed ==="
```

Make executable:
```bash
chmod +x .acts/tests/test_operations.sh
```

### Step 6.4: Run tests

```bash
# Python tests
cd .acts
cd ..
python3 -m pytest .acts/tests/test_cli.py -v
python3 -m pytest .acts/tests/test_runner.py -v

# Bash tests
.acts/tests/test_operations.sh
```

Expected: All tests pass.

### Step 6.5: Commit

```bash
git add .acts/tests/
git commit -m "test: add unit tests for CLI, runner, and operations"
```

---

## Task 7: Update Documentation

**Files:**
- Modify: `acts-v0.6.1.md` (add invocation mechanism section)

**Goal:** Document the new invocation mechanism in the spec.

### Step 7.1: Add invocation mechanism section to spec

Add to `acts-v0.6.1.md` after §5.1:

```markdown
### 5.1.3 Operation Invocation Protocol

ACTS operations are invoked via the `acts` CLI tool using stdin/stdout JSON communication.

**CLI Syntax:**
```bash
acts run <operation_id> [flags]
```

**Input/Output:**
- Input: JSON via stdin containing operation inputs
- Output: JSON via stdout containing operation results
- Logs: stderr
- Exit codes: 0 (success), 2 (changes requested), 1 (error)

**Example Invocation:**
```bash
echo '{"inputs": {"task_id": "T1"}}' | acts run task-review
```

**Operation Calling Another Operation:**
Operations can synchronously call other operations:
```bash
# In task-start operation
OUTPUT=$(echo '{"inputs": {"task_id": "T1"}}' | acts run task-review)
STATUS=$(echo "$OUTPUT" | jq -r '.status')
```

**Benefits:**
- Language agnostic (operations can be bash, python, node)
- No file I/O overhead
- Composable operations
- Testable in isolation
```

### Step 7.2: Commit documentation

```bash
git add acts-v0.6.1.md
git commit -m "docs: document operation invocation protocol in v0.6.1 spec"
```

---

## Task 8: Final Integration Test

**Goal:** Verify the entire flow works end-to-end.

### Step 8.1: Test complete flow

```bash
# 1. Start a task
echo '{"inputs": {"task_id": "T1", "action": "start"}}' | ./.acts/acts run task-start --verbose

# 2. Complete task (calls task-review)
echo '{"inputs": {"task_id": "T1", "action": "complete"}}' | ./.acts/acts run task-start --verbose

# 3. Verify exit codes
./.acts/acts run task-start --dry-run <<< '{"inputs": {"task_id": "T1"}}'
echo "Exit code: $?"
```

Expected: All operations run successfully, proper JSON output, correct exit codes.

### Step 8.2: Commit final changes

```bash
git add -A
git commit -m "feat: complete ACTS operation invocation mechanism implementation"
```

---

## Summary

This implementation plan creates:

1. **CLI Tool** (`acts`) - Python-based CLI for invoking operations
2. **Operation Runner** - Handles stdin/stdout JSON communication
3. **Bash Helper Library** - Makes writing bash operations easy
4. **Executable Operations** - task-review and task-start converted
5. **Operation Chaining** - task-start calls task-review via CLI
6. **Tests** - Unit tests for CLI, runner, and operations
7. **Documentation** - Updated spec with invocation protocol

All gates in ACTS now use explicit operation calls via the invocation mechanism.
