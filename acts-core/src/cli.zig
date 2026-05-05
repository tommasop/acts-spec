const std = @import("std");

pub const Command = struct {
    name: []const u8,
    args: std.StringHashMap([]const u8),
    flags: std.StringHashMap(bool),
    positional: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) Command {
        return .{
            .name = "",
            .args = std.StringHashMap([]const u8).init(allocator),
            .flags = std.StringHashMap(bool).init(allocator),
            .positional = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Command) void {
        self.args.deinit();
        self.flags.deinit();
        self.positional.deinit();
    }

    pub fn get(self: *Command, key: []const u8) ?[]const u8 {
        return self.args.get(key);
    }

    pub fn hasFlag(self: *Command, flag: []const u8) bool {
        return self.flags.get(flag) orelse false;
    }
};

pub fn parse(allocator: std.mem.Allocator, args: []const []const u8) !Command {
    var cmd = Command.init(allocator);
    
    if (args.len > 0) {
        cmd.name = args[0];
    }
    
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        
        if (std.mem.startsWith(u8, arg, "--")) {
            const key = arg[2..];
            if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                try cmd.args.put(key, args[i + 1]);
                i += 1;
            } else {
                try cmd.flags.put(key, true);
            }
        } else if (std.mem.startsWith(u8, arg, "-")) {
            const key = arg[1..];
            try cmd.flags.put(key, true);
        } else {
            try cmd.positional.append(arg);
        }
    }
    
    return cmd;
}
