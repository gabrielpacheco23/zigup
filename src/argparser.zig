const std = @import("std");
const builtin = std.builtin;

fn advanceWhileNot(cond: *const fn (char: u8) bool, src: []const u8, curr: *usize) void {
    while (curr.* < src.len and !cond(src[curr.*])) curr.* += 1;
}

fn advanceWhile(cond: *const fn (char: u8) bool, src: []const u8, curr: *usize) void {
    while (curr.* < src.len and cond(src[curr.*])) curr.* += 1;
}

fn expectStr(expected: []const u8, src: []const u8, curr: *usize) void {
    const len = expected.len;
    if (!std.mem.eql(u8, expected, src[curr.* .. curr.* + len])) {
        std.debug.print("Expected {s}, found {s}\n", .{ expected, src[curr.* .. curr.* + len] });
        std.process.exit(1);
    }

    curr.* += len - 1;
}

pub const Command = struct {
    name: []const u8,
};

pub const Option = struct {
    name: []const u8,
    value: ?[]const u8,
};

pub const Flag = struct {
    name: []const u8,
};

pub const Arg = union(enum) {
    command: Command,
    option: Option,
    flag: Flag,
};

pub fn parseArgs(alloc: std.mem.Allocator, src: []const u8) !std.ArrayList(Arg) {
    var args: std.ArrayList(Arg) = .init(alloc);
    errdefer args.deinit();

    var curr: usize = 0;
    var start: usize = 0;
    var i: usize = 0;

    while (curr < src.len) : (curr += 1) {
        advanceWhile(std.ascii.isWhitespace, src, &curr);
        start = curr;

        if (!std.ascii.isAlphanumeric(src[curr])) {
            expectStr("--", src, &curr);
            advanceWhileNot(std.ascii.isWhitespace, src, &curr);

            const tokName = src[start + 2 .. curr];
            advanceWhile(std.ascii.isWhitespace, src, &curr);

            if (curr == src.len or src[curr] == 0 or src[curr] == '-') {
                try args.append(.{ .flag = .{ .name = tokName } });
                curr -= 1;
            } else {
                start = curr;
                advanceWhileNot(std.ascii.isWhitespace, src, &curr);
                const optName = src[start..curr];

                try args.append(.{ .option = .{
                    .name = tokName,
                    .value = optName,
                } });
            }
        } else {
            advanceWhileNot(std.ascii.isWhitespace, src, &curr);
            const cmdName = src[start..curr];

            try args.append(.{
                .command = .{ .name = cmdName },
            });
        }
        i += 1;
    }
    return args;
}
