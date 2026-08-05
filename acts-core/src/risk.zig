const std = @import("std");

pub const RiskTier = enum {
    LOW,
    MEDIUM,
    HIGH,
    CRITICAL,

    pub fn label(self: RiskTier) []const u8 {
        return switch (self) {
            .LOW => "LOW",
            .MEDIUM => "MEDIUM",
            .HIGH => "HIGH",
            .CRITICAL => "CRITICAL",
        };
    }

    pub fn fromString(s: []const u8) RiskTier {
        if (std.mem.eql(u8, s, "LOW")) return .LOW;
        if (std.mem.eql(u8, s, "MEDIUM")) return .MEDIUM;
        if (std.mem.eql(u8, s, "HIGH")) return .HIGH;
        if (std.mem.eql(u8, s, "CRITICAL")) return .CRITICAL;
        return .MEDIUM;
    }

    /// Rank for ordering / threshold comparisons.
    pub fn rank(self: RiskTier) u8 {
        return switch (self) {
            .LOW => 1,
            .MEDIUM => 2,
            .HIGH => 3,
            .CRITICAL => 4,
        };
    }
};

pub const RiskInput = struct {
    file_count: usize,
    diff_additions: usize,
    cross_repo_edges: usize,
    high_complexity_symbols: usize,
    verified: bool,
};

/// Compute a risk tier for a change. This is a local heuristic (no CBM needed);
/// the CBM-backed trace data can be folded in by callers who have it.
///
///   CRITICAL  — >= 2 cross-repo edges
///   HIGH      — 1 cross-repo edge, OR large diff (>= 30 files), OR many
///               high-complexity symbols
///   MEDIUM    — moderately large diff (>= 8 files) or a couple complex symbols
///   LOW       — small, verified, no cross-repo edges
pub fn classify(input: RiskInput) RiskTier {
    if (input.cross_repo_edges >= 2) return .CRITICAL;
    if (input.cross_repo_edges >= 1) return .HIGH;
    if (input.file_count >= 30 or input.high_complexity_symbols >= 5) return .HIGH;
    if (input.file_count >= 8 or input.high_complexity_symbols >= 2) return .MEDIUM;
    if (input.diff_additions >= 400) return .MEDIUM;
    return .LOW;
}

test "classify low small verified change" {
    const t = classify(.{
        .file_count = 2,
        .diff_additions = 80,
        .cross_repo_edges = 0,
        .high_complexity_symbols = 0,
        .verified = true,
    });
    try std.testing.expectEqual(RiskTier.LOW, t);
}

test "classify medium on file count" {
    const t = classify(.{
        .file_count = 12,
        .diff_additions = 200,
        .cross_repo_edges = 0,
        .high_complexity_symbols = 0,
        .verified = true,
    });
    try std.testing.expectEqual(RiskTier.MEDIUM, t);
}

test "classify high on single cross-repo edge" {
    const t = classify(.{
        .file_count = 1,
        .diff_additions = 10,
        .cross_repo_edges = 1,
        .high_complexity_symbols = 0,
        .verified = true,
    });
    try std.testing.expectEqual(RiskTier.HIGH, t);
}

test "classify critical on two cross-repo edges" {
    const t = classify(.{
        .file_count = 3,
        .diff_additions = 50,
        .cross_repo_edges = 2,
        .high_complexity_symbols = 1,
        .verified = true,
    });
    try std.testing.expectEqual(RiskTier.CRITICAL, t);
}
