# Human Review Experience (HRE) Design Spec

**Date:** 2026-05-15
**Status:** Draft
**Version:** 1.0

## Overview

Replace the basic `acts review` terminal prompt with a structured, vim-navigable review interface that shows agent rationale, runs quality gates automatically, displays previous rejections, and presents multi-file diffs with hunk-level navigation.

## Architecture

### Module Structure

```
acts-core/src/
├── main.zig          # Command dispatch (calls review.run)
├── review.zig        # NEW: Review orchestration and display
├── quality.zig       # NEW: Auto-detect and run quality gates
└── db.zig            # Extended: rationale + rejection queries
```

### Data Flow

```
handleReview()
  ├── review.gatherContext()     # Load task, files, rationale, rejections
  ├── quality.detectAndRun()     # Auto-detect + run tests/lint/typecheck/build
  ├── review.displayOverview()   # Show file list + quality gate results
  ├── review.displayFile()       # Show per-file diff with hunks
  └── review.promptDecision()    # Interactive vim-style navigation
```

## Quality Gate Auto-Detection

### Detection Order

Quality gate checks project root for indicators in this order:

| Indicator | Detects | Command |
|-----------|---------|---------|
| `Makefile` | Make-based | `make test`, `make lint`, `make check`, `make build` |
| `package.json` | Node.js | `npm test`, `npm run lint`, `npx tsc --noEmit`, `npm run build` |
| `Cargo.toml` | Rust | `cargo test`, `cargo clippy`, `cargo check`, `cargo build` |
| `go.mod` | Go | `go test ./...`, `golangci-lint run`, `go build ./...` |
| `pyproject.toml` | Python | `pytest`, `ruff check .`, `mypy .`, `python -m build` |
| `requirements.txt` | Python (legacy) | `pytest`, `ruff check .`, `mypy .` |
| `pom.xml` | Java/Maven | `mvn test`, `mvn checkstyle:check`, `mvn compile` |
| `build.gradle` | Java/Gradle | `gradle test`, `gradle check`, `gradle build` |
| `*.sln` | .NET | `dotnet test`, `dotnet build` |
| `mix.exs` | Elixir | `mix test`, `mix credo`, `mix compile` |

### Execution Model

- Each stage runs sequentially with a 60-second timeout
- Output captured (stdout + stderr) for display
- Exit code determines pass/fail/warn (exit 0 = pass, 1-99 = fail, 100+ = warn)
- Results stored in `QualityResult` struct:

```zig
pub const QualityStage = enum { test, lint, typecheck, build };

pub const QualityResult = struct {
    stage: QualityStage,
    command: []const u8,
    status: enum { pass, fail, warn, skipped },
    exit_code: i32,
    output: []const u8,
    duration_ms: u64,
};
```

### Configuration Override

If `.acts/acts.json` contains `quality_gate`, use it instead of auto-detection:

```json
{
  "quality_gate": {
    "test": "zig build test",
    "lint": "zig fmt --check src/",
    "typecheck": null,
    "build": "zig build"
  }
}
```

## Terminal Display

### Overview Panel

Shown first when `acts review <task-id>` runs:

```
Review: T3 — Add JWT refresh token rotation
=============================================
Quality Gate:  ✓ test (1.2s)  ✓ lint (0.8s)  ✓ typecheck (2.1s)  ⚠ build (3.4s, 2 warnings)

Agent Rationale:
  "Rotating refresh tokens on each use to prevent token replay attacks."

Files (4):
  1. src/auth/token.zig          +42 -8   [HIGH]   Core auth logic
  2. src/auth/session.zig        +15 -3   [MEDIUM] Session management
  3. tests/auth_test.zig         +28 -2   [LOW]    Test coverage
  4. .acts/acts.json             +2  -0   [LOW]    Config change

Previous Rejections: 1
  - Rejected by tommasop on 2026-05-14: "Missing token expiry validation"

Navigate: j/k scroll  ]c/[c hunks  ]f/[f files  a approve  r reject  q quit  ? help
```

### Per-File View

```
─── 1/4: src/auth/token.zig ─────────────────────────────────────────────
Risk: HIGH — Modifies core authentication logic (3 other files depend on this)

─── Hunk 1/3: generateRefreshToken (lines 45-67) ───────────────────────
  42   fn validateToken(self: *Store, token: []const u8) !bool {
  43       return self.tokens.get(token) != null;
  44   }
  45
- 46   fn generateRefreshToken(self: *Store, user: User) ![]const u8 {
- 47       const token = try self.random.bytes(32);
- 48       return try hexEncode(token);
+ 46   fn generateRefreshToken(self: *Store, user: User) !RefreshToken {
+ 47       const token = try self.random.bytes(32);
+ 48       const encoded = try hexEncode(token);
+ 49       return RefreshToken{
+ 50           .value = encoded,
+ 51           .expires = self.clock.now() + REFRESH_TTL,
+ 52           .rotated = false,
+ 53       };
  54   }

Annotation: Type changed from []const u8 to RefreshToken struct — breaking change for consumers
```

### Previous Rejection Panel

If task was previously rejected, shown before file overview:

```
Previous Rejection (2026-05-14 by tommasop):
  "Missing token expiry validation"

Changes since rejection:
  - Added expires field to RefreshToken struct
  - Added validateExpiry() in token.zig:78
  - Added test case in auth_test.zig:142
```

### Color Scheme (ANSI)

| Element | Color |
|---------|-------|
| Additions (`+`) | Green |
| Deletions (`-`) | Red |
| File headers | Cyan |
| Line numbers | White (dim) |
| Annotations | Yellow |
| Risk HIGH | Red |
| Risk MEDIUM | Yellow |
| Risk LOW | Green |
| Quality pass | Green |
| Quality fail | Red |
| Quality warn | Yellow |
| Status bar | White on blue background |

## Navigation Keys (Vim-Style)

### Scrolling

| Key | Action |
|-----|--------|
| `j` | Line down |
| `k` | Line up |
| `Ctrl-d` | Half-page down |
| `Ctrl-u` | Half-page up |
| `gg` | Go to top |
| `G` | Go to bottom |

### Hunk Navigation

| Key | Action |
|-----|--------|
| `]c` | Next hunk |
| `[c` | Previous hunk |

### File Navigation

| Key | Action |
|-----|--------|
| `]f` | Next file |
| `[f` | Previous file |
| `:files` | Show file overview |

### Actions

| Key | Action |
|-----|--------|
| `a` | Approve and quit |
| `r` | Reject and quit |
| `q` | Quit without decision |
| `:qa` | Approve and quit (alt) |
| `:cq` | Reject and quit (alt) |

### Context

| Key | Action |
|-----|--------|
| `Ctrl-g` | Show position (file X/Y, hunk A/B) |
| `?` | Show help |

## Terminal Implementation

### Raw Mode

Use POSIX termios for raw input:

```zig
const std = @import("std");
const posix = std.posix;

pub fn enterRawMode() !posix.termios {
    const stdin = std.io.getStdIn();
    const orig = try posix.tcgetattr(stdin.handle);
    var raw = orig;
    raw.lflag &= ~(@as(posix.tcflag_t, @bitCast(posix.Termios.Lflag.ECHO |
        posix.Termios.Lflag.ICANON)));
    raw.cc[@intFromEnum(posix.VMIN)] = 1;
    raw.cc[@intFromEnum(posix.VTIME)] = 0;
    try posix.tcsetattr(stdin.handle, .FLUSH, raw);
    return orig;
}
```

### Key Parsing

Handle escape sequences for special keys:

```
ESC [ A → Up      ESC [ B → Down
ESC [ C → Right   ESC [ D → Left
ESC [ 6 ~ → PgDn  ESC [ 5 ~ → PgUp
```

Multi-key sequences (`gg`, `]c`, `[c`, `:qa`, `:cq`, `:files`) use a 500ms timeout buffer. After first key press, subsequent characters are collected until timeout or Enter (for ex-mode commands starting with `:`). Ex-mode commands are terminated by Enter; all other multi-key sequences are matched against a trie of known bindings.

### Screen Rendering

- Clear screen with ANSI escape `\x1b[2J\x1b[H`
- Use `\x1b[?25l` / `\x1b[?25h` to hide/show cursor
- Render to buffer, then write once per frame to avoid flicker
- Status bar pinned to bottom row

## Database Extensions

### New Fields

No schema changes needed. Uses existing tables:

- **Rationale**: Stored in `decisions` table with `topic = 'rationale'`
- **Rejections**: Stored in `gate_checkpoints` with `status = 'changes_requested'`
- **Files**: Already in `task_files`

### New Queries

```zig
pub fn getRationale(self: *Database, allocator: std.mem.Allocator, task_id: []const u8) !?[]const u8
pub fn getPreviousRejections(self: *Database, allocator: std.mem.Allocator, task_id: []const u8) ![]Rejection
pub fn getFilesForTask(self: *Database, allocator: std.mem.Allocator, task_id: []const u8) ![][]const u8
```

## Risk Assessment

### Calculation

Risk level based on:

1. **File type weight**: Files matching patterns `*auth*`, `*db*`, `*config*`, `*schema*`, `*security*`, `*crypto*`, `*middleware*`, `*router*` = HIGH weight. Files matching `*test*`, `*spec*`, `*mock*`, `*.md`, `*.txt`, `*.json` (non-config) = LOW weight. All others = MEDIUM weight.
2. **Dependency count**: File appears in `task_files` for 3+ other DONE tasks = +1 risk level
3. **Lines changed**: >100 lines = +1 risk level
4. **File age**: File not modified in 90+ days (per `git log -1 --format=%ct -- <file>`) = +1 risk level

Max risk level is HIGH.

## Error Handling

| Scenario | Behavior |
|----------|----------|
| No quality gate detected | Show "No quality gate detected — skipping" |
| Quality gate timeout (60s) | Show "⏱ Timed out after 60s" — mark as warn |
| Git not available | Fall back to file content comparison |
| Task has no files | Show "No files recorded — review manually" |
| Terminal too small (< 40 cols) | Show error and exit |
| Non-TTY stdin | Show error: "Review requires interactive terminal" |

## main.zig Changes

Replace existing `handleReview` (lines 509-646) with:

```zig
fn handleReview(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) { /* usage */ }
    const task_id = args[0];

    // Open DB, verify task exists (existing logic)
    // ...

    const review_mod = @import("review.zig");
    try review_mod.run(allocator, &database, task_id);
}
```

## Testing Strategy

1. **Quality detection**: Unit tests for each project type indicator
2. **Key parsing**: Unit tests for escape sequence decoding
3. **Risk calculation**: Unit tests for risk level computation
4. **Integration**: End-to-end test with a sample git repo and staged changes
