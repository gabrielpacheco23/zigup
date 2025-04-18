const std = @import("std");
const builtin = std.builtin;

fn advanceWhileNot(cond: *const fn (char: u8) bool, src: []const u8, curr: *usize) void {
    while (curr.* < src.len and !cond(src[curr.*])) curr.* += 1;
}

fn advanceWhile(cond: *const fn (char: u8) bool, src: []const u8, curr: *usize) void {
    while (curr.* < src.len and cond(src[curr.*])) curr.* += 1;
}

fn expectStr(expected: []const u8, src: []const u8, curr: *usize) !void {
    const len = expected.len;
    if (!std.mem.eql(u8, expected, src[curr.* .. curr.* + len])) {
        std.debug.print("Expected {s}, found {s}", .{ expected, src[curr.* .. curr.* + len] });
        return error.ExpectStrError;
    }

    curr.* += len - 1;
}

const ArgType = enum {
    Command,
    Option,
    Flag,
};

const Arg = struct {
    type: ArgType,
    name: []const u8,
    value: ?[]const u8,
};

pub fn parseArgs(alloc: std.mem.Allocator, src: []const u8) !std.ArrayList(Arg) {
    var args: std.ArrayList(Arg) = .init(alloc);
    errdefer args.deinit();

    var curr: usize = 0;
    var start: usize = 0;

    while (curr < src.len) : (curr += 1) {
        advanceWhile(std.ascii.isWhitespace, src, &curr);
        start = curr;

        if (!std.ascii.isAlphanumeric(src[curr])) {
            try expectStr("--", src, &curr);
            advanceWhileNot(std.ascii.isWhitespace, src, &curr);

            const tokName = src[start..curr];
            advanceWhile(std.ascii.isWhitespace, src, &curr);

            if (curr == src.len or src[curr] == 0 or src[curr] == '-') {
                try args.append(.{
                    .type = .Flag,
                    .name = src[start + 2 .. curr],
                    .value = null,
                });
                curr -= 1;
            } else {
                start = curr;
                advanceWhileNot(std.ascii.isWhitespace, src, &curr);
                const optName = src[start..curr];
                try args.append(.{
                    .type = .Option,
                    .name = tokName,
                    .value = optName,
                });
            }
        } else {
            advanceWhileNot(std.ascii.isWhitespace, src, &curr);
            try args.append(.{
                .type = .Command,
                .name = src[start..curr],
                .value = null,
            });
        }
    }
    return args;
}

pub fn main() !void {
    var dba: std.heap.DebugAllocator(.{}) = .init;
    defer _ = dba.deinit();
    const alloc = dba.allocator();

    // const arg_list = "zigup install --quiet --version 0.13.0 --colors";
    const arguments = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, arguments);

    const args_str = try std.mem.join(alloc, " ", arguments[1..]);
    defer alloc.free(args_str);

    std.debug.print("{s}\n", .{args_str});
    const args = try parseArgs(alloc, args_str);
    defer args.deinit();

    for (args.items) |arg| {
        if (arg.value) |value| {
            std.debug.print("------\nArg: name: {s}, type: {}, value: {s}\n", .{ arg.name, arg.type, value });
        } else {
            std.debug.print("------\nArg: name: {s}, type: {}\n", .{ arg.name, arg.type });
        }
    }
    std.debug.print("------\n", .{});
}
