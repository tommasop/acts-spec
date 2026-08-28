const std = @import("std");
const git = @import("git.zig");
const archify = @import("archify.zig");

const RAW_BASE = "https://raw.githubusercontent.com/tommasop/acts-spec/master";

/// Files (relative to the acts-spec repo root) that make up the OpenCode
/// integration. `acts setup` installs them into the target project so a user
/// does not need to clone acts-spec.
pub const integration_files = [_][]const u8{
    ".opencode/plugins/acts.js",
    ".opencode/skills/acts/SKILL.md",
    ".opencode/commands/acts-context.md",
    ".opencode/commands/acts-verify.md",
    ".opencode/commands/acts-change.md",
    ".opencode/commands/acts-stack.md",
    ".opencode/commands/acts-zeplin.md",
    ".opencode/commands/acts-diagram.md",
};

/// The AGENTS.md ACTS v2 section that `acts setup` injects (idempotent).
pub const agents_section =
    \\## ACTS Integration (v2)
    \\
    \\This project uses ACTS v2 — a **git-native coordination protocol** for agent-aided development. Git is the system of record: a *stack* is a feature (a **feature branch** off `master`), a *change* is one unit of agent work (**a checkpoint on that branch**). Verification is the gate; context is served on demand.
    \\
    \\### Rules
    \\- Agent MUST load context before writing code: `acts context <change>`
    \\- Agent MUST NOT submit a change for review until `acts verify <change>` passes
    \\- Agent MUST record a session note + checkpoint before ending: `acts note` / `acts checkpoint`
    \\- Agent MUST stay within the change's scope: `acts scope <change> <file>`
    \\- Agent MUST get developer approval on the PR before `acts approve` / `acts stack land`
    \\- Agent MUST run `acts validate` before finishing
    \\
    \\### ACTS v2 Commands
    \\- `acts stack create <id> [-t <title>]` — Start a new stack (feature branch + manifest)
    \\- `acts stack status [--json]` — Show stack tree + change statuses
    \\- `acts stack land` — Merge the whole feature branch once all changes are APPROVED
    \\- `acts change add <id> -t <title> [--accept <criteria>]` — Add a change (checkpoint on the feature branch)
    \\- `acts change status [<id>]` — Show change details
    \\- `acts verify [<id>] [--all]` — Run quality gates; record evidence (GATE for review)
    \\- `acts review <id>` — Submit/update the stack's ONE PR (feature vs base; requires verify to pass)
    \\- `acts approve <id>` — Mark approved after human PR review
    \\- `acts rework <id>` — Reopen for rework (clears approval)
    \\- `acts risk <id>` — Compute the change's risk tier (LOW/MEDIUM/HIGH/CRITICAL)
    \\- `acts context [<id>]` — Emit scoped context pack (durable task state)
    \\- `acts note <id> -m <text>` — Append a session note
    \\- `acts checkpoint <id> -s <summary>` — Record a status checkpoint
    \\- `acts redirect <id> --accept <criteria>` — Update scope mid-flight without context loss
    \\- `acts scope <id> <file>` — Check file ownership (derived from diffs)
    \\- `acts diagram <id> [--delta] [--attach]` — Render the change's architecture impact via archify (HTML; `--attach` comments on the PR)
    \\- `acts validate` — Validate manifest + branch consistency
    \\
    \\Status Values: TODO, IN_PROGRESS, VERIFIED, IN_REVIEW, APPROVED, MERGED
    \\
;

pub const github_workflow =
    \\name: opencode
    \\
    \\on:
    \\  issue_comment:
    \\    types: [created]
    \\  pull_request_review_comment:
    \\    types: [created]
    \\
    \\jobs:
    \\  opencode:
    \\    if: |
    \\      contains(github.event.comment.body, '/oc') ||
    \\      contains(github.event.comment.body, '/opencode')
    \\    runs-on: ubuntu-latest
    \\    permissions:
    \\      id-token: write
    \\      contents: write
    \\      pull-requests: write
    \\      issues: write
    \\    steps:
    \\      - name: Checkout repository
    \\        uses: actions/checkout@v6
    \\        with:
    \\          fetch-depth: 1
    \\          persist-credentials: false
    \\
    \\      - name: Run OpenCode
    \\        uses: anomalyco/opencode/github@latest
    \\        env:
    \\          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
    \\        with:
    \\          model: anthropic/claude-sonnet-4-20250514
    \\
;

pub const SetupError = error{
    CurlMissing,
    DownloadFailed,
    CopyFailed,
    WriteFailed,
    SelfCopyFailed,
    BinDirUnwritable,
};

fn mkdirp(dir: []const u8) void {
    std.fs.cwd().makePath(dir) catch {};
}

fn writeFile(path: []const u8, data: []const u8) !void {
    if (std.fs.path.dirname(path)) |d| mkdirp(d);
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = data });
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Resolve the first `name` on PATH (like `which`). Returns null if not found.
fn which(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    const res = git.run(allocator, &.{ "which", name }, 512) catch return null;
    if (res.exit_code != 0) return null;
    const t = std.mem.trim(u8, res.stdout, " \n\r");
    if (t.len == 0) return null;
    return allocator.dupe(u8, t) catch null;
}

/// Download a file over HTTP via curl into `dest` (creating parent dirs).
fn curlDownload(allocator: std.mem.Allocator, url: []const u8, dest: []const u8) !void {
    if (!git.hasTool(allocator, "curl")) return SetupError.CurlMissing;
    if (std.fs.path.dirname(dest)) |d| mkdirp(d);
    const res = try git.run(allocator, &.{ "curl", "-fsSL", url, "-o", dest }, 1 << 20);
    if (res.exit_code != 0) return SetupError.DownloadFailed;
    if (!fileExists(dest)) return SetupError.DownloadFailed;
}

/// Copy a file from a local acts-spec checkout (used for offline/dev testing).
fn copyFromSource(allocator: std.mem.Allocator, source_root: []const u8, rel: []const u8, dest: []const u8) !void {
    const src = try std.fs.path.join(allocator, &.{ source_root, rel });
    defer allocator.free(src);
    const data = std.fs.cwd().readFileAlloc(allocator, src, 1 << 20) catch return SetupError.CopyFailed;
    defer allocator.free(data);
    try writeFile(dest, data);
}

pub const SetupOptions = struct {
    target_dir: []const u8,
    source_dir: ?[]const u8 = null, // local acts-spec checkout
    with_github: bool = false,
    force: bool = false,
    no_install: bool = false, // skip global binary install
    bin_dir: []const u8 = "~/.local/bin", // global install location
    with_archify: bool = false, // also install the archify diagram renderer skill
};

/// Main entry: `acts setup [dir] [--source <acts-spec>] [--github] [--force] [--bin-dir <dir>] [--no-install] [--with-archify]`
pub fn run(allocator: std.mem.Allocator, opts: SetupOptions) !void {
    // 0. Global binary install (acts self-copy + cbm download), unless --no-install.
    if (!opts.no_install) {
        try installBinaries(allocator, opts.bin_dir);
    }

    // 1. Install the OpenCode integration files into the target project.
    const installed = try installIntegrationFiles(allocator, opts);
    _ = installed;

    // 2. Merge opencode.json (plugins + permission).
    try configureOpencode(allocator, opts);

    // 3. Inject AGENTS.md section (idempotent).
    try configureAgentsMd(allocator, opts);

    // 4. Optional GitHub workflow.
    if (opts.with_github) {
        try configureGithub(allocator, opts);
    }

    // 5. Optional archify renderer skill (diagrams for `acts diagram`).
    if (opts.with_archify) {
        try installArchify(allocator, opts.target_dir);
    }
}

/// Install the archify renderer skill into the target project via
/// `npx skills add tt-a1i/archify`. Idempotent; requires node/npx.
pub fn installArchify(allocator: std.mem.Allocator, target_dir: []const u8) !void {
    if (archify.findRenderer(allocator, target_dir)) |r| {
        std.debug.print("archify renderer already installed: {s}\n", .{r});
        return;
    }
    if (!git.hasTool(allocator, "node") or !git.hasTool(allocator, "npx")) {
        std.debug.print("note: `node`/`npx` not found — skipping archify install. Run `acts archify install` later.\n", .{});
        return;
    }
    std.debug.print("installing archify skill via npx (diagram renderer for `acts diagram`)…\n", .{});
    const res = git.run(allocator, archify.installCmdArgs(), 1 << 24) catch {
        std.debug.print("note: `npx skills add` failed — run `acts archify install` later.\n", .{});
        return;
    };
    if (res.exit_code != 0) {
        std.debug.print("note: `npx skills add` failed: {s} — run `acts archify install` later.\n", .{std.mem.trim(u8, res.stderr, " \n\r")});
        return;
    }
    if (archify.findRenderer(allocator, target_dir)) |r| {
        std.debug.print("archify installed: {s}\n", .{r});
    } else {
        std.debug.print("note: archify install ran but renderer not found under `.opencode/skills/archify`.\n", .{});
    }
}

/// Install `acts` + `cbm` into a global bin dir. `acts` copies its own
/// executable; `cbm` is downloaded from its official installer.
fn installBinaries(allocator: std.mem.Allocator, bin_dir_raw: []const u8) !void {
    const bin_dir = try expandHome(allocator, bin_dir_raw);
    defer allocator.free(bin_dir);

    // --- acts: copy the running binary ---
    const self_path = std.fs.selfExePathAlloc(allocator) catch return SetupError.SelfCopyFailed;
    defer allocator.free(self_path);
    const acts_dest = try std.fs.path.join(allocator, &.{ bin_dir, "acts" });
    defer allocator.free(acts_dest);

    const self_canon = std.fs.realpathAlloc(allocator, self_path) catch self_path;
    defer if (!std.mem.eql(u8, self_canon, self_path)) allocator.free(self_canon);

    // If the destination is already the running executable (e.g. `acts` is
    // installed at ~/.local/bin/acts and that's the default bin dir), skip the
    // self-copy — overwriting a running binary fails with FileBusy (ETXTBSY).
    const already_here = if (std.fs.realpathAlloc(allocator, acts_dest) catch null) |d| blk: {
        defer allocator.free(d);
        break :blk std.mem.eql(u8, d, self_canon);
    } else false;

    if (already_here) {
        std.debug.print("acts already installed at {s} — skipping self-copy.\n", .{acts_dest});
    } else {
        // Write via a temp file + rename so we never clobber a running binary
        // and never leave a partial file on failure.
        const tmp = try std.fs.path.join(allocator, &.{ bin_dir, ".acts-install.tmp" });
        defer allocator.free(tmp);
        try writeFile(tmp, std.fs.cwd().readFileAlloc(allocator, self_path, 1 << 30) catch return SetupError.SelfCopyFailed);
        std.posix.fchmodat(std.posix.AT.FDCWD, tmp, 0o755, 0) catch {};
        std.fs.cwd().rename(tmp, acts_dest) catch |e| {
            std.fs.cwd().deleteFile(tmp) catch {};
            return e;
        };
        std.debug.print("acts installed to {s}\n", .{acts_dest});
    }

    // Warn if another `acts` earlier in PATH shadows the one we just ensured
    // at acts_dest (e.g. a stale v1 install in /usr/local/bin). This prevents
    // silently resolving to the wrong binary after setup.
    const resolved = which(allocator, "acts");
    if (resolved) |r| {
        defer allocator.free(r);
        const r_canon = std.fs.realpathAlloc(allocator, r) catch r;
        defer if (!std.mem.eql(u8, r_canon, r)) allocator.free(r_canon);
        const d_canon = std.fs.realpathAlloc(allocator, acts_dest) catch acts_dest;
        defer if (!std.mem.eql(u8, d_canon, acts_dest)) allocator.free(d_canon);
        if (!std.mem.eql(u8, r_canon, d_canon)) {
            std.debug.print(
                "warning: `{s}` is earlier in PATH and shadows {s}.\n  Remove it or reorder PATH so {s} comes first.\n",
                .{ r, acts_dest, bin_dir },
            );
        }
    }

    // --- cbm: run its official installer (best-effort) ---
    // cbm decides its own canonical install location (~/.local/bin or
    // ~/.cache/codebase-memory-mcp/bin). We run the installer and then detect
    // where the binary landed so the message is accurate.
    const cbm_url = "https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh";
    const cbm_script = try std.fs.path.join(allocator, &.{ bin_dir, "cbm-install.sh" });
    defer allocator.free(cbm_script);
    curlDownload(allocator, cbm_url, cbm_script) catch |e| switch (e) {
        error.DownloadFailed, error.CurlMissing => {
            std.debug.print("note: could not download cbm installer (offline?) — run `acts setup` later.\n", .{});
            return;
        },
        else => return e,
    };
    const res = try git.run(allocator, &.{ "bash", cbm_script, "--skip-config" }, 1 << 20);
    _ = res;
    const found = findCbm(allocator);
    if (found) |f| {
        std.debug.print("cbm installed at: {s}\n", .{f});
    } else {
        std.debug.print("note: cbm install ran but binary not found on PATH — run `acts setup` later.\n", .{});
    }
}

fn findCbm(allocator: std.mem.Allocator) ?[]const u8 {
    const candidates = [_][]const u8{
        "~/.local/bin/codebase-memory-mcp",
        "~/.cache/codebase-memory-mcp/bin/codebase-memory-mcp",
    };
    for (candidates) |c| {
        const p = expandHome(allocator, c) catch continue;
        if (fileExists(p)) return p;
    }
    const res = git.run(allocator, &.{ "which", "codebase-memory-mcp" }, 512) catch return null;
    if (res.exit_code == 0) {
        const t = std.mem.trim(u8, res.stdout, " \n\r");
        if (t.len > 0) return t;
    }
    return null;
}

fn expandHome(allocator: std.mem.Allocator, p: []const u8) ![]const u8 {
    if (std.mem.startsWith(u8, p, "~/")) {
        const home = std.posix.getenv("HOME") orelse return p;
        return std.fs.path.join(allocator, &.{ home, p[2..] });
    }
    return allocator.dupe(u8, p);
}

/// Install each integration file into the target project (from GitHub or a
/// local acts-spec checkout). Returns number of files written.
fn installIntegrationFiles(allocator: std.mem.Allocator, opts: SetupOptions) !usize {
    var count: usize = 0;
    for (integration_files) |rel| {
        const dest = try std.fs.path.join(allocator, &.{ opts.target_dir, rel });
        defer allocator.free(dest);

        if (!opts.force and fileExists(dest)) continue; // idempotent

        if (opts.source_dir) |src| {
            copyFromSource(allocator, src, rel, dest) catch |e| switch (e) {
                error.CopyFailed => continue,
                else => return e,
            };
        } else {
            const url = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ RAW_BASE, rel });
            defer allocator.free(url);
            curlDownload(allocator, url, dest) catch |e| switch (e) {
                error.CurlMissing => {
                    std.debug.print("note: `curl` not found — cannot fetch {s}. Install curl or use `--source <acts-spec-dir>`.\n", .{rel});
                    continue;
                },
                error.DownloadFailed => {
                    std.debug.print("note: could not fetch {s} from {s} — offline or file missing. Use `--source <acts-spec-dir>` to copy from a local checkout.\n", .{ rel, RAW_BASE });
                    continue;
                },
                else => return e,
            };
        }
        count += 1;
    }
    return count;
}

/// Merge (or create) opencode.json: ensure the plugins (superpowers + acts +
/// cbm) and the skill permission are present.
fn configureOpencode(allocator: std.mem.Allocator, opts: SetupOptions) !void {
    const cfg_path = try std.fs.path.join(allocator, &.{ opts.target_dir, "opencode.json" });
    defer allocator.free(cfg_path);

    var root: std.json.ObjectMap = undefined;
    var parsed: ?std.json.Parsed(std.json.Value) = null;
    defer if (parsed) |*p| p.deinit();

    if (fileExists(cfg_path)) {
        const content = std.fs.cwd().readFileAlloc(allocator, cfg_path, 1 << 20) catch null;
        if (content) |c| {
            defer allocator.free(c);
            const p = std.json.parseFromSlice(std.json.Value, allocator, c, .{}) catch null;
            if (p) |pp| {
                parsed = pp;
                if (pp.value == .object) {
                    root = pp.value.object;
                }
            }
        }
    }
    if (parsed == null) {
        root = std.json.ObjectMap.init(allocator);
    }

    // Ensure plugins array contains the entries.
    const gop = try root.getOrPut("plugin");
    if (!gop.found_existing) gop.value_ptr.* = .{ .array = std.json.Array.init(allocator) };
    const plugins = &gop.value_ptr.*.array;
    const want = [_][]const u8{
        "superpowers@git+https://github.com/obra/superpowers.git",
        "./.opencode/plugins/acts.js",
    };
    for (want) |w| {
        var found = false;
        for (plugins.items) |item| {
            if (item == .string and std.mem.eql(u8, item.string, w)) {
                found = true;
                break;
            }
        }
        if (!found) try plugins.append(.{ .string = w });
    }

    // Ensure CBM is exposed as a native MCP server (replaces the old cbm plugin).
    const mgop = try root.getOrPut("mcp");
    if (!mgop.found_existing) mgop.value_ptr.* = .{ .object = std.json.ObjectMap.init(allocator) };
    const mcp = &mgop.value_ptr.*.object;
    const cgop = try mcp.getOrPut("codebase-memory-mcp");
    if (!cgop.found_existing) {
        var server = std.json.ObjectMap.init(allocator);
        try server.put("type", .{ .string = "local" });
        var cmd = std.json.Array.init(allocator);
        try cmd.append(.{ .string = "codebase-memory-mcp" });
        try server.put("command", .{ .array = cmd });
        try server.put("enabled", .{ .bool = true });
        cgop.value_ptr.* = .{ .object = server };
    }

    // Ensure permission.skill.acts = allow
    const pgop = try root.getOrPut("permission");
    if (!pgop.found_existing) pgop.value_ptr.* = .{ .object = std.json.ObjectMap.init(allocator) };
    const perm = &pgop.value_ptr.*.object;
    const sgop = try perm.getOrPut("skill");
    if (!sgop.found_existing) sgop.value_ptr.* = .{ .object = std.json.ObjectMap.init(allocator) };
    try sgop.value_ptr.*.object.put("acts", .{ .string = "allow" });

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    const v: std.json.Value = .{ .object = root };
    try std.json.stringify(v, .{ .whitespace = .indent_2 }, buf.writer());
    try buf.append('\n');
    try writeFile(cfg_path, buf.items);
}

/// Inject (or replace) the ACTS v2 section in AGENTS.md. Idempotent.
fn configureAgentsMd(allocator: std.mem.Allocator, opts: SetupOptions) !void {
    const agents_path = try std.fs.path.join(allocator, &.{ opts.target_dir, "AGENTS.md" });
    defer allocator.free(agents_path);

    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();

    if (fileExists(agents_path)) {
        const existing = std.fs.cwd().readFileAlloc(allocator, agents_path, 1 << 20) catch "";
        defer allocator.free(existing);
        try content.appendSlice(existing);
    }

    const marker = "## ACTS Integration (v2)";
    const idx = std.mem.indexOf(u8, content.items, marker);
    if (idx) |i| {
        // Replace from the marker to the next "\n## " heading (or end).
        var end = content.items.len;
        if (std.mem.indexOfPos(u8, content.items, i + marker.len, "\n## ")) |j| {
            end = j;
        }
        // Keep content before marker, insert new section, keep the rest.
        var out = std.ArrayList(u8).init(allocator);
        defer out.deinit();
        try out.appendSlice(content.items[0..i]);
        try out.appendSlice(agents_section);
        try out.appendSlice(content.items[end..]);
        try writeFile(agents_path, out.items);
    } else {
        // Append a blank line + section if not present.
        if (content.items.len > 0 and content.items[content.items.len - 1] != '\n') {
            try content.append('\n');
        }
        try content.append('\n');
        try content.appendSlice(agents_section);
        try writeFile(agents_path, content.items);
    }
}

/// Write the GitHub Actions workflow for OpenCode integration.
fn configureGithub(allocator: std.mem.Allocator, opts: SetupOptions) !void {
    const wf_path = try std.fs.path.join(allocator, &.{ opts.target_dir, ".github", "workflows", "opencode.yml" });
    defer allocator.free(wf_path);
    try writeFile(wf_path, github_workflow);
    std.debug.print("\nWrote .github/workflows/opencode.yml\n", .{});
    std.debug.print("Next: run `opencode github install` to register the GitHub App + secrets.\n", .{});
}

test "expandHome resolves tilde" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const home = std.posix.getenv("HOME") orelse return error.SkipZigTest;
    const p = try expandHome(a, "~/bin/acts");
    try std.testing.expect(std.mem.startsWith(u8, p, home));
    try std.testing.expect(std.mem.endsWith(u8, p, "/bin/acts"));

    const plain = try expandHome(a, "/opt/bin/acts");
    try std.testing.expectEqualStrings("/opt/bin/acts", plain);
}

test "integration files list covers plugins + skill + commands" {
    var seen_plugins = false;
    var seen_skill = false;
    var seen_diagram = false;
    for (integration_files) |f| {
        if (std.mem.eql(u8, f, ".opencode/plugins/acts.js")) seen_plugins = true;
        if (std.mem.eql(u8, f, ".opencode/skills/acts/SKILL.md")) seen_skill = true;
        if (std.mem.eql(u8, f, ".opencode/commands/acts-diagram.md")) seen_diagram = true;
    }
    try std.testing.expect(seen_plugins);
    try std.testing.expect(seen_skill);
    try std.testing.expect(seen_diagram);
    try std.testing.expect(integration_files.len >= 9);
}

test "agents_section mentions verify gate and setup commands" {
    try std.testing.expect(std.mem.indexOf(u8, agents_section, "acts verify") != null);
    try std.testing.expect(std.mem.indexOf(u8, agents_section, "acts context") != null);
    try std.testing.expect(std.mem.indexOf(u8, agents_section, "acts risk") != null);
}
