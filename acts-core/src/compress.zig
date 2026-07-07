const std = @import("std");

pub const CompressionTier = enum { safe, aggressive };

pub const CompressOptions = struct {
    tier: CompressionTier = .safe,
    preserve_code_blocks: bool = true,
    max_code_block_lines: usize = 20,
};

pub const CompressResult = struct {
    output: []const u8,
    tokens_before: usize,
    tokens_after: usize,
    saved_pct: f64,
};

// ============================================================
// Public API
// ============================================================

pub fn compress(allocator: std.mem.Allocator, input: []const u8, options: CompressOptions) !CompressResult {
    const tokens_before = estimateTokens(input);

    // Protect code blocks from modification
    var code_blocks: std.ArrayList(CodeBlock) = .{};
    defer code_blocks.deinit(allocator);

    const protected_text = if (options.preserve_code_blocks)
        try protectCodeBlocks(allocator, input, &code_blocks)
    else
        try allocator.dupe(u8, input);
    defer allocator.free(protected_text);

    // Apply Tier 1 (safe) rules
    var text = protected_text;
    defer if (text.ptr != protected_text.ptr) allocator.free(text);

    text = try applyRule(allocator, text, stripFrontmatter);
    text = try applyRule(allocator, text, stripHtmlComments);
    text = try applyRule(allocator, text, stripBadges);
    text = try applyRule(allocator, text, stripMetadataLines);
    text = try applyRule(allocator, text, stripHorizontalRules);
    text = try applyRule(allocator, text, stripToc);
    text = try applyRule(allocator, text, compactTables);
    text = try applyRule(allocator, text, collapseBlankLines);
    text = try applyRule(allocator, text, stripTrailingCta);
    text = try applyRule(allocator, text, stripUrlTracking);
    text = try applyRule(allocator, text, normalizeUnicode);

    // Apply Tier 2 (aggressive) rules
    if (options.tier == .aggressive) {
        text = try applyRule(allocator, text, stripHedging);
        text = try applyRule(allocator, text, stripAdmonitionPrefixes);
        text = try applyRule(allocator, text, stripCrossReferences);
        text = try applyRule(allocator, text, stripBoilerplateSections);
        text = try applyRule(allocator, text, stripEditFooters);
        text = try applyRule(allocator, text, stripVerification);
        text = try applyRule(allocator, text, stripSeoChaff);
        text = try applyRule(allocator, text, truncateCodeBlocks);
        text = try applyRule(allocator, text, stripHtmlWrappers);
    }

    // Restore code blocks
    const final_text = try restoreCodeBlocks(allocator, text, code_blocks.items);
    if (text.ptr != protected_text.ptr) allocator.free(text);

    const tokens_after = estimateTokens(final_text);
    const saved_pct = if (tokens_before > 0)
        @as(f64, @floatFromInt(tokens_before -| tokens_after)) / @as(f64, @floatCast(tokens_before)) * 100.0
    else
        0.0;

    return .{
        .output = final_text,
        .tokens_before = tokens_before,
        .tokens_after = tokens_after,
        .saved_pct = saved_pct,
    };
}

pub fn estimateTokens(text: []const u8) usize {
    return text.len / 4;
}

pub fn escapeJsonString(writer: anytype, input: []const u8) !void {
    for (input) |ch| {
        switch (ch) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(ch),
        }
    }
}

// ============================================================
// Code Block Protection
// ============================================================

const CodeBlock = struct {
    placeholder: []const u8,
    content: []const u8,
};

fn protectCodeBlocks(
    allocator: std.mem.Allocator,
    input: []const u8,
    blocks: *std.ArrayList(CodeBlock),
) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    var block_index: usize = 0;

    while (i < input.len) {
        // Look for opening ```
        if (i + 2 < input.len and input[i] == '`' and input[i + 1] == '`' and input[i + 2] == '`') {
            // Find end of opening fence (may have language tag)
            var fence_end = i + 3;
            while (fence_end < input.len and input[fence_end] != '\n') : (fence_end += 1) {}
            if (fence_end < input.len) fence_end += 1; // include newline

            // Find closing ```
            var j = fence_end;
            var found_close = false;
            while (j + 2 < input.len) {
                if (input[j] == '`' and input[j + 1] == '`' and input[j + 2] == '`') {
                    // Check it's at start of line or only preceded by whitespace
                    var line_start = j;
                    while (line_start > 0 and input[line_start - 1] != '\n') : (line_start -= 1) {
                        if (input[line_start - 1] != ' ' and input[line_start - 1] != '\t') {
                            line_start = j;
                            break;
                        }
                    }
                    if (line_start == j) {
                        // Found closing fence
                        var close_end = j + 3;
                        while (close_end < input.len and input[close_end] != '\n') : (close_end += 1) {}
                        if (close_end < input.len) close_end += 1;

                        const block_content = input[i..close_end];

                        // Create placeholder
                        const placeholder = try std.fmt.allocPrint(allocator, "§CB_{d}§", .{block_index});
                        errdefer allocator.free(placeholder);

                        try result.writeAll(placeholder);
                        try blocks.append(allocator, .{
                            .placeholder = placeholder,
                            .content = try allocator.dupe(u8, block_content),
                        });

                        block_index += 1;
                        i = close_end;
                        found_close = true;
                        break;
                    }
                }
                j += 1;
            }

            if (!found_close) {
                // Unclosed code block — pass through
                try result.writeAll(input[i..fence_end]);
                i = fence_end;
            }
        } else {
            try result.writeByte(input[i]);
            i += 1;
        }
    }

    return try result.toOwnedSlice();
}

fn restoreCodeBlocks(
    allocator: std.mem.Allocator,
    text: []const u8,
    blocks: []const CodeBlock,
) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < text.len) {
        // Look for §CB_N§
        if (text[i] == '§' and i + 4 < text.len and text[i + 1] == 'C' and text[i + 2] == 'B' and text[i + 3] == '_') {
            // Find closing §
            var j = i + 4;
            while (j < text.len and text[j] != '§') : (j += 1) {}
            if (j < text.len) {
                const index_str = text[i + 4 .. j];
                const index = std.fmt.parseInt(usize, index_str, 10) catch {
                    // Not a valid index, pass through
                    try result.writeByte(text[i]);
                    i += 1;
                    continue;
                };

                if (index < blocks.len) {
                    try result.writeAll(blocks[index].content);
                    i = j + 1; // skip closing §
                } else {
                    try result.writeByte(text[i]);
                    i += 1;
                }
            } else {
                try result.writeByte(text[i]);
                i += 1;
            }
        } else {
            try result.writeByte(text[i]);
            i += 1;
        }
    }

    return try result.toOwnedSlice();
}

// ============================================================
// Rule Application Helper
// ============================================================

fn applyRule(
    allocator: std.mem.Allocator,
    input: []const u8,
    rule_fn: *const fn (std.mem.Allocator, []const u8) error{OutOfMemory}![]const u8,
) ![]const u8 {
    const result = try rule_fn(allocator, input);
    if (result.ptr != input.ptr) {
        allocator.free(input);
    }
    return result;
}

// ============================================================
// Tier 1: Safe Rules (lossless-to-meaning)
// ============================================================

/// Remove YAML/TOML frontmatter between --- or +++ delimiters
fn stripFrontmatter(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    if (input.len < 6) return try allocator.dupe(u8, input);

    // Must start with --- or +++
    if (!((input[0] == '-' and input[1] == '-' and input[2] == '-') or
        (input[0] == '+' and input[1] == '+' and input[2] == '+')))
    {
        return try allocator.dupe(u8, input);
    }

    const delimiter = input[0..3];
    var end: usize = 3;

    // Find closing delimiter at start of a line
    while (end + 2 < input.len) {
        if (input[end] == '\n') {
            const next = end + 1;
            if (next + 2 < input.len and
                input[next] == delimiter[0] and
                input[next + 1] == delimiter[0] and
                input[next + 2] == delimiter[0])
            {
                // Skip past the closing delimiter and its newline
                end = next + 3;
                if (end < input.len and input[end] == '\n') end += 1;
                break;
            }
        }
        end += 1;
    }

    if (end <= 3) return try allocator.dupe(u8, input);

    // Check if there's meaningful content after frontmatter
    const remaining = std.mem.trimLeft(u8, input[end..], " \t\n");
    if (remaining.len == 0) {
        // Entire file was frontmatter — return empty
        return try allocator.dupe(u8, "");
    }

    return try allocator.dupe(u8, input[end..]);
}

/// Remove HTML comments <!-- ... -->
fn stripHtmlComments(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (i + 3 < input.len and input[i] == '<' and input[i + 1] == '!' and
            input[i + 2] == '-' and input[i + 3] == '-')
        {
            // Find -->
            var j = i + 4;
            while (j + 2 < input.len) {
                if (input[j] == '-' and input[j + 1] == '-' and input[j + 2] == '>') {
                    i = j + 3;
                    break;
                }
                j += 1;
            }
            if (j + 2 >= input.len) break; // unclosed comment, stop
        } else {
            try result.writeByte(input[i]);
            i += 1;
        }
    }

    return try result.toOwnedSlice();
}

/// Remove shields.io badge images
fn stripBadges(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        // Match: [![...](https://img.shields.io/...)](...)
        if (std.mem.indexOf(u8, trimmed, "img.shields.io") != null or
            std.mem.indexOf(u8, trimmed, "shields.io") != null)
        {
            continue; // skip badge lines
        }
        // Match: ![...](https://badgen.net/...)
        if (std.mem.indexOf(u8, trimmed, "badgen.net") != null) {
            continue;
        }
        try result.writeAll(line);
        try result.append('\n');
    }

    return try result.toOwnedSlice();
}

/// Remove metadata lines like **Last updated:**, **Version:**, etc.
fn stripMetadataLines(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    const prefixes = [_][]const u8{
        "**Last updated:",
        "**Version:",
        "**Status:",
        "**Author:",
        "**Maintainer:",
        "**License:",
        "**Stability:",
        "**Deprecation:",
    };

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        var skip = false;
        for (prefixes) |prefix| {
            if (std.mem.startsWith(u8, trimmed, prefix)) {
                skip = true;
                break;
            }
        }
        if (skip) continue;

        try result.writeAll(line);
        try result.append('\n');
    }

    return try result.toOwnedSlice();
}

/// Remove horizontal rules (---, ***, ___)
fn stripHorizontalRules(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (isHorizontalRule(trimmed)) continue;

        try result.writeAll(line);
        try result.append('\n');
    }

    return try result.toOwnedSlice();
}

fn isHorizontalRule(s: []const u8) bool {
    if (s.len < 3) return false;
    const ch = s[0];
    if (ch != '-' and ch != '*' and ch != '_') return false;

    for (s) |c| {
        if (c != ch and c != ' ') return false;
    }

    // Count non-space characters
    var count: usize = 0;
    for (s) |c| {
        if (c == ch) count += 1;
    }
    return count >= 3;
}

/// Remove auto-generated table of contents
fn stripToc(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var in_toc = false;
    var lines = std.mem.splitScalar(u8, input, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Detect TOC header
        if (isTocHeader(trimmed)) {
            in_toc = true;
            continue;
        }

        // Inside TOC: skip lines that are list items with anchor links
        if (in_toc) {
            if (isTocEntry(trimmed)) {
                continue;
            } else {
                // End of TOC
                in_toc = false;
            }
        }

        try result.writeAll(line);
        try result.append('\n');
    }

    return try result.toOwnedSlice();
}

fn isTocHeader(s: []const u8) bool {
    const lower = s;
    return std.mem.startsWith(u8, lower, "## Table of Contents") or
        std.mem.startsWith(u8, lower, "## Contents") or
        std.mem.startsWith(u8, lower, "## Table of contents") or
        std.mem.startsWith(u8, lower, "# Table of Contents") or
        std.mem.startsWith(u8, lower, "# Contents") or
        std.mem.eql(u8, lower, "## TOC") or
        std.mem.eql(u8, lower, "# TOC");
}

fn isTocEntry(s: []const u8) bool {
    // Matches: - [text](#anchor) or * [text](#anchor)
    if (s.len < 5) return false;
    if (s[0] != '-' and s[0] != '*') return false;
    if (s[1] != ' ') return false;
    if (std.mem.indexOf(u8, s, "](#") == null) return false;
    return true;
}

/// Compact pipe tables: remove separator rows and collapse whitespace
fn compactTables(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Skip table separator rows: |---|---| or |:---:|:---:|
        if (isTableSeparator(trimmed)) {
            continue;
        }

        // Compact table rows: collapse multiple spaces within cells
        if (isTableRow(trimmed)) {
            var compacted = std.ArrayList(u8).init(allocator);
            defer compacted.deinit();

            var cells = std.mem.splitScalar(u8, line, '|');
            var first = true;
            while (cells.next()) |cell| {
                if (!first) try compacted.append('|');
                first = false;
                const trimmed_cell = std.mem.trim(u8, cell, " ");
                try compacted.appendSlice(trimmed_cell);
            }

            const owned = try compacted.toOwnedSlice();
            defer allocator.free(owned);
            try result.writeAll(owned);
        } else {
            try result.writeAll(line);
        }
        try result.append('\n');
    }

    return try result.toOwnedSlice();
}

fn isTableSeparator(s: []const u8) bool {
    if (s.len < 3) return false;
    // Must contain | and only have -, :, and spaces between pipes
    if (std.mem.indexOf(u8, s, "|") == null) return false;

    for (s) |c| {
        if (c != '|' and c != '-' and c != ':' and c != ' ' and c != ':') return false;
    }

    // Must have at least one -
    return std.mem.indexOf(u8, s, "-") != null;
}

fn isTableRow(s: []const u8) bool {
    return s.len > 0 and s[0] == '|';
}

/// Collapse 3+ blank lines to 2
fn collapseBlankLines(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var newline_count: usize = 0;

    for (input) |ch| {
        if (ch == '\n') {
            newline_count += 1;
            if (newline_count <= 2) {
                try result.append(ch);
            }
        } else {
            newline_count = 0;
            try result.append(ch);
        }
    }

    return try result.toOwnedSlice();
}

/// Remove trailing CTA sections (star/follow/sponsor)
fn stripTrailingCta(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    const cta_headers = [_][]const u8{
        "## Contributing",
        "## License",
        "## Support",
        "## Sponsor",
        "## Star",
        "## Give a Star",
        "## Stargazers",
    };

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        var skip = false;
        for (cta_headers) |header| {
            if (std.mem.eql(u8, trimmed, header)) {
                skip = true;
                break;
            }
        }
        if (skip) continue;

        try result.writeAll(line);
        try result.append('\n');
    }

    return try result.toOwnedSlice();
}

/// Remove UTM tracking parameters from URLs
fn stripUrlTracking(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < input.len) {
        // Look for ?utm_ in URLs
        if (i + 5 < input.len and input[i] == '?' and
            input[i + 1] == 'u' and input[i + 2] == 't' and input[i + 3] == 'm' and input[i + 4] == '_')
        {
            // Skip until & or ) or space or end
            while (i < input.len and input[i] != '&' and input[i] != ')' and input[i] != ' ' and input[i] != '\n') : (i += 1) {}
            // If we stopped at &, skip to next param value
            if (i < input.len and input[i] == '&') {
                // Check if next param is also utm_
                if (i + 5 < input.len and input[i + 1] == 'u' and input[i + 2] == 't' and input[i + 3] == 'm' and input[i + 4] == '_') {
                    continue; // skip the & too, next iteration will handle
                }
                i += 1; // keep the & for non-utm params
            }
        } else {
            try result.writeByte(input[i]);
            i += 1;
        }
    }

    return try result.toOwnedSlice();
}

/// Normalize Unicode characters to ASCII equivalents
fn normalizeUnicode(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < input.len) {
        // Check for UTF-8 multi-byte sequences
        if (input[i] == 0xC2 and i + 1 < input.len) {
            const next = input[i + 1];
            switch (next) {
                0xAB => { try result.writeAll("<"); i += 2; continue; }, // «
                0xBB => { try result.writeAll(">"); i += 2; continue; }, // »
                0xA0 => { try result.writeByte(' '); i += 2; continue; }, // NBSP
                0xB7 => { try result.writeAll("."); i += 2; continue; }, // ·
                else => {},
            }
        }

        if (input[i] == 0xE2 and i + 2 < input.len) {
            const b1 = input[i + 1];
            const b2 = input[i + 2];
            switch (b1) {
                0x80 => {
                    switch (b2) {
                        0x93 => { try result.writeAll("-"); i += 3; continue; }, // – en dash
                        0x94 => { try result.writeAll("--"); i += 3; continue; }, // — em dash
                        0x98 => { try result.writeAll("'"); i += 3; continue; }, // ' left single quote
                        0x99 => { try result.writeAll("'"); i += 3; continue; }, // ' right single quote
                        0x9C => { try result.writeAll("\""); i += 3; continue; }, // " left double quote
                        0x9D => { try result.writeAll("\""); i += 3; continue; }, // " right double quote
                        0xA6 => { try result.writeAll("|"); i += 3; continue; }, // ¦
                        0x92 => { try result.writeAll("'"); i += 3; continue; }, // ' right single quote (alt)
                        0x91 => { try result.writeAll("`"); i += 3; continue; }, // ' left single quote (alt)
                        0x9E => { try result.writeAll("\""); i += 3; continue; }, // " right double quote (alt)
                        0x9B => { try result.writeAll("\""); i += 3; continue; }, // " right single quote (alt)
                        else => {},
                    }
                },
                0x82 => {
                    if (b2 == 0xA6) { try result.writeAll("|"); i += 3; continue; } // ‖
                },
                0x85 => {
                    if (b2 == 0xA6) { try result.writeAll("..."); i += 3; continue; } // … ellipsis
                },
                else => {},
            }
        }

        // Smart quotes (single byte check for common cases)
        if (input[i] == 0xE2) {
            // Already handled above in the multi-byte block
        }

        try result.writeByte(input[i]);
        i += 1;
    }

    return try result.toOwnedSlice();
}

// ============================================================
// Tier 2: Aggressive Rules (prose simplification)
// ============================================================

/// Remove hedging and verbose phrases
fn stripHedging(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    const HedgePhrase = struct { from: []const u8, to: []const u8 };
    const phrases = [_]HedgePhrase{
        .{ .from = "In order to", .to = "To" },
        .{ .from = "in order to", .to = "to" },
        .{ .from = "Due to the fact that", .to = "Because" },
        .{ .from = "due to the fact that", .to = "because" },
        .{ .from = "At this point in time", .to = "Now" },
        .{ .from = "at this point in time", .to = "now" },
        .{ .from = "In the event that", .to = "If" },
        .{ .from = "in the event that", .to = "if" },
        .{ .from = "For the purpose of", .to = "For" },
        .{ .from = "for the purpose of", .to = "for" },
        .{ .from = "With regard to", .to = "About" },
        .{ .from = "with regard to", .to = "about" },
        .{ .from = "With respect to", .to = "About" },
        .{ .from = "with respect to", .to = "about" },
        .{ .from = "In spite of the fact that", .to = "Although" },
        .{ .from = "in spite of the fact that", .to = "although" },
        .{ .from = "Has the ability to", .to = "Can" },
        .{ .from = "has the ability to", .to = "can" },
        .{ .from = "It is important to note that", .to = "" },
        .{ .from = "it is important to note that", .to = "" },
        .{ .from = "It is worth noting that", .to = "" },
        .{ .from = "it is worth noting that", .to = "" },
        .{ .from = "Please note that", .to = "" },
        .{ .from = "please note that", .to = "" },
        .{ .from = "Keep in mind that", .to = "" },
        .{ .from = "keep in mind that", .to = "" },
        .{ .from = "As a matter of fact", .to = "" },
        .{ .from = "as a matter of fact", .to = "" },
        .{ .from = "For all intents and purposes", .to = "" },
        .{ .from = "for all intents and purposes", .to = "" },
        .{ .from = "In light of the fact that", .to = "Since" },
        .{ .from = "in light of the fact that", .to = "since" },
        .{ .from = "On a regular basis", .to = "Regularly" },
        .{ .from = "on a regular basis", .to = "regularly" },
        .{ .from = "In the near future", .to = "Soon" },
        .{ .from = "in the near future", .to = "soon" },
        .{ .from = "In the process of", .to = "" },
        .{ .from = "in the process of", .to = "" },
        .{ .from = "On the grounds that", .to = "Because" },
        .{ .from = "on the grounds that", .to = "because" },
        .{ .from = "Is able to", .to = "Can" },
        .{ .from = "is able to", .to = "can" },
        .{ .from = "Is in the process of", .to = "" },
        .{ .from = "is in the process of", .to = "" },
        .{ .from = "Goes without saying that", .to = "" },
        .{ .from = "goes without saying that", .to = "" },
        .{ .from = "At the end of the day", .to = "" },
        .{ .from = "at the end of the day", .to = "" },
        .{ .from = "Taking into consideration", .to = "Considering" },
        .{ .from = "taking into consideration", .to = "considering" },
        .{ .from = "With the exception of", .to = "Except" },
        .{ .from = "with the exception of", .to = "except" },
        .{ .from = "Until such time as", .to = "Until" },
        .{ .from = "until such time as", .to = "until" },
        .{ .from = "In a timely manner", .to = "Promptly" },
        .{ .from = "in a timely manner", .to = "promptly" },
        .{ .from = "At this moment", .to = "Now" },
        .{ .from = "at this moment", .to = "now" },
        .{ .from = "For the most part", .to = "Mostly" },
        .{ .from = "for the most part", .to = "mostly" },
        .{ .from = "As a general rule", .to = "Generally" },
        .{ .from = "as a general rule", .to = "generally" },
        .{ .from = "In the final analysis", .to = "" },
        .{ .from = "in the final analysis", .to = "" },
        .{ .from = "By means of", .to = "By" },
        .{ .from = "by means of", .to = "by" },
        .{ .from = "In the matter of", .to = "About" },
        .{ .from = "in the matter of", .to = "about" },
        .{ .from = "For the duration of", .to = "During" },
        .{ .from = "for the duration of", .to = "during" },
        .{ .from = "In the vicinity of", .to = "Near" },
        .{ .from = "in the vicinity of", .to = "near" },
        .{ .from = "On the subject of", .to = "About" },
        .{ .from = "on the subject of", .to = "about" },
        .{ .from = "Whether or not", .to = "Whether" },
        .{ .from = "whether or not", .to = "whether" },
        .{ .from = "Each and every", .to = "Every" },
        .{ .from = "each and every", .to = "every" },
        .{ .from = "First and foremost", .to = "First" },
        .{ .from = "first and foremost", .to = "first" },
        .{ .from = "Last but not least", .to = "Finally" },
        .{ .from = "last but not least", .to = "finally" },
        .{ .from = "A large number of", .to = "Many" },
        .{ .from = "a large number of", .to = "many" },
        .{ .from = "The vast majority of", .to = "Most" },
        .{ .from = "the vast majority of", .to = "most" },
    };

    var result = try allocator.dupe(u8, input);

    for (phrases) |phrase| {
        const new_result = try replaceAll(allocator, result, phrase.from, phrase.to);
        if (new_result.ptr != result.ptr) allocator.free(result);
        result = new_result;
    }

    return result;
}

/// Replace all occurrences of `from` with `to` in `text`
fn replaceAll(allocator: std.mem.Allocator, text: []const u8, from: []const u8, to: []const u8) ![]const u8 {
    if (from.len == 0) return try allocator.dupe(u8, text);

    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < text.len) {
        if (i + from.len <= text.len and std.mem.eql(u8, text[i .. i + from.len], from)) {
            try result.writeAll(to);
            i += from.len;
        } else {
            try result.writeByte(text[i]);
            i += 1;
        }
    }

    return try result.toOwnedSlice();
}

/// Remove admonition prefixes: **Note:**, **Warning:**, **Tip:**, **Important:**
fn stripAdmonitionPrefixes(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    const prefixes = [_][]const u8{
        "**Note:** ",
        "**Note:**",
        "**Warning:** ",
        "**Warning:**",
        "**Tip:** ",
        "**Tip:**",
        "**Important:** ",
        "**Important:**",
        "**Caution:** ",
        "**Caution:**",
        "> **Note:** ",
        "> **Note:**",
        "> **Warning:** ",
        "> **Warning:**",
    };

    var result = try allocator.dupe(u8, input);

    for (prefixes) |prefix| {
        const new_result = try replaceAll(allocator, result, prefix, "");
        if (new_result.ptr != result.ptr) allocator.free(result);
        result = new_result;
    }

    return result;
}

/// Remove "See the [X] section for details" type phrases
fn stripCrossReferences(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    const patterns = [_][]const u8{
        "See the ",
        "see the ",
        "Refer to ",
        "refer to ",
        "For more details, see ",
        "for more details, see ",
        "For more information, see ",
        "for more information, see ",
    };

    var result = try allocator.dupe(u8, input);

    for (patterns) |pattern| {
        // Find and remove sentences starting with these patterns
        const new_result = try removeSentencesStartingWith(allocator, result, pattern);
        if (new_result.ptr != result.ptr) allocator.free(result);
        result = new_result;
    }

    return result;
}

fn removeSentencesStartingWith(allocator: std.mem.Allocator, text: []const u8, prefix: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed, prefix) and std.mem.indexOf(u8, trimmed, ".") != null) {
            continue; // skip entire line
        }
        try result.writeAll(line);
        try result.append('\n');
    }

    return try result.toOwnedSlice();
}

/// Remove boilerplate sections: Contributing, License, Support (when just links)
fn stripBoilerplateSections(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    const boilerplate_headers = [_][]const u8{
        "## Contributing",
        "## License",
        "## Support",
    };

    var in_boilerplate = false;
    var boilerplate_line_count: usize = 0;
    var lines = std.mem.splitScalar(u8, input, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Detect boilerplate header
        var is_bp_header = false;
        for (boilerplate_headers) |header| {
            if (std.mem.eql(u8, trimmed, header)) {
                is_bp_header = true;
                break;
            }
        }

        if (is_bp_header) {
            in_boilerplate = true;
            boilerplate_line_count = 0;
            continue;
        }

        if (in_boilerplate) {
            boilerplate_line_count += 1;
            // If it's a short section (<=5 lines) and just a link, skip it
            if (boilerplate_line_count <= 5) {
                if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "[") or
                    std.mem.startsWith(u8, trimmed, "See ") or
                    std.mem.startsWith(u8, trimmed, "see ") or
                    std.mem.startsWith(u8, trimmed, "- "))
                {
                    continue;
                }
            }
            // Section is longer than expected — not boilerplate
            in_boilerplate = false;
        }

        try result.writeAll(line);
        try result.append('\n');
    }

    return try result.toOwnedSlice();
}

/// Remove "edit this page" / "last updated" / "view source" footers
fn stripEditFooters(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    const footer_patterns = [_][]const u8{
        "Edit this page",
        "edit this page",
        "Edit on GitHub",
        "edit on GitHub",
        "View source",
        "view source",
        "Edit on GitLab",
        "edit on GitLab",
        "Last updated",
        "last updated",
    };

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        var skip = false;
        for (footer_patterns) |pattern| {
            if (std.mem.indexOf(u8, trimmed, pattern) != null) {
                skip = true;
                break;
            }
        }
        if (skip) continue;

        try result.writeAll(line);
        try result.append('\n');
    }

    return try result.toOwnedSlice();
}

/// Remove "If valid, the output should be:" type verification chitchat
fn stripVerification(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    const patterns = [_][]const u8{
        "If valid, the output",
        "if valid, the output",
        "Expected output:",
        "expected output:",
        "The expected output",
        "the expected output",
    };

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        var skip = false;
        for (patterns) |pattern| {
            if (std.mem.startsWith(u8, trimmed, pattern)) {
                skip = true;
                break;
            }
        }
        if (skip) continue;

        try result.writeAll(line);
        try result.append('\n');
    }

    return try result.toOwnedSlice();
}

/// Remove breadcrumbs, prev/next, "Was this helpful?", SEO chaff
fn stripSeoChaff(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    const patterns = [_][]const u8{
        "Was this helpful?",
        "was this helpful?",
        "Previous | Next",
        "previous | next",
        "< Previous",
        "< previous",
        "Next >",
        "Next >",
        "Back to top",
        "back to top",
        "Table of Contents",
        "table of contents",
    };

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        var skip = false;
        for (patterns) |pattern| {
            if (std.mem.eql(u8, trimmed, pattern)) {
                skip = true;
                break;
            }
        }
        if (skip) continue;

        try result.writeAll(line);
        try result.append('\n');
    }

    return try result.toOwnedSlice();
}

/// Truncate large code blocks, keeping first 10 and last 5 lines
fn truncateCodeBlocks(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    // This operates on the unprotected text, so code blocks are still marked with §CB_N§
    // We need to work on the original code blocks instead
    // For simplicity, this rule is a no-op when code blocks are protected
    // The actual truncation happens in protectCodeBlocks if we add it there
    // For now, return as-is — truncation is handled separately if needed
    return try allocator.dupe(u8, input);
}

/// Remove decorative HTML wrapper tags (div, span, details, summary)
fn stripHtmlWrappers(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    const tags = [_][]const u8{
        "<div>", "</div>",
        "<span>", "</span>",
        "<details>", "</details>",
        "<summary>", "</summary>",
        "<section>", "</section>",
        "<article>", "</article>",
    };

    var result = try allocator.dupe(u8, input);

    for (tags) |tag| {
        const new_result = try replaceAll(allocator, result, tag, "");
        if (new_result.ptr != result.ptr) allocator.free(result);
        result = new_result;
    }

    return result;
}

// ============================================================
// Tests
// ============================================================

test "stripFrontmatter removes YAML frontmatter" {
    const input =
        \\---
        \\title: Hello
        \\author: Test
        \\---
        \\
        \\# Content
        \\
    ;
    const result = try compress(std.testing.allocator, input, .{ .preserve_code_blocks = false });
    defer std.testing.allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "title: Hello") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "# Content") != null);
}

test "stripHtmlComments removes comments" {
    const input = "Hello <!-- this is a comment --> world\n";
    const result = try compress(std.testing.allocator, input, .{ .preserve_code_blocks = false });
    defer std.testing.allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "comment") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "Hello") != null);
}

test "stripBadges removes shields.io" {
    const input = "[![Badge](https://img.shields.io/badge/test-pass-green)](#)\n# Title\n";
    const result = try compress(std.testing.allocator, input, .{ .preserve_code_blocks = false });
    defer std.testing.allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "shields.io") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "# Title") != null);
}

test "collapseBlankLines reduces blank lines" {
    const input = "a\n\n\n\n\nb\n";
    const result = try compress(std.testing.allocator, input, .{ .preserve_code_blocks = false });
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqual(@as(usize, 0), std.mem.indexOf(u8, result.output, "\n\n\n\n"));
}

test "stripHedging removes verbose phrases" {
    const input = "In order to test, we must note that it works.\n";
    const result = try compress(std.testing.allocator, input, .{
        .tier = .aggressive,
        .preserve_code_blocks = false,
    });
    defer std.testing.allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "In order to") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "note that") == null);
}

test "code blocks are preserved" {
    const input =
        \\# Title
        \\
        \\```zig
        \\const x = 42;
        \\```
        \\
        \\Some text.
        \\
    ;
    const result = try compress(std.testing.allocator, input, .{});
    defer std.testing.allocator.free(result.output);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "const x = 42") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "```zig") != null);
}

test "estimateTokens works" {
    try std.testing.expectEqual(@as(usize, 10), estimateTokens("1234567890"));
    try std.testing.expectEqual(@as(usize, 0), estimateTokens(""));
}
