const std = @import("std");
const builtin = @import("builtin");
const json = std.json;
const ArrayList = std.ArrayList;

const utils = @import("utils.zig");
const downloader = @import("downloader.zig");
const argparser = @import("argparser.zig");

const stdout = std.io.getStdOut().writer();
const ZIG_WEBSITE: []const u8 = "https://ziglang.org";
const DOWNLOAD_PATH: []const u8 = "/download/index.json";
const ZIGUP_VERSION: []const u8 = "0.1.0";

const signal = @cImport({
    @cInclude("signal.h");
});

// TODO: MAKE FN TO INSTALL `ZLS`
// COMMANDS: git clone https://github.com/zigtools/zls
//           cd zls
//           git checkout 0.14.0
//           zig build -Doptimize=ReleaseSafe

pub fn main() !void {
    var dba: std.heap.DebugAllocator(.{}) = .init;
    defer _ = dba.deinit();
    const allocator = dba.allocator();

    const arguments = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, arguments);

    const args_str = try std.mem.join(allocator, " ", arguments[1..]);
    defer allocator.free(args_str);

    const args = try argparser.parseArgs(allocator, args_str);
    defer args.deinit();

    if (args.items.len == 0) {
        try displayHelp();
        return;
    }

    var cmd: ?argparser.Command = null;
    var opt: ?argparser.Option = null;
    var flags: std.ArrayList(?argparser.Flag) = .init(allocator);
    defer flags.deinit();

    for (args.items) |arg| {
        try switch (arg) {
            .command => cmd = arg.command,
            .option => opt = arg.option,
            .flag => flags.append(arg.flag),
        };
    }

    if (cmd) |command| {
        if (std.mem.eql(u8, command.name, "upgrade")) {
            std.debug.print("[INFO] Fetching...\n", .{});
            // try upgradeZig(allocator);
            try installVersion(allocator, "latest");
        } else if (std.mem.eql(u8, command.name, "install")) {
            if (opt) |option| {
                if (std.mem.eql(u8, option.name, "version")) {
                    if (option.value) |value| {
                        std.debug.print("[INFO] Fetching...\n", .{});
                        try installVersion(allocator, value);
                    } else {
                        try displayHelp();
                    }
                }
            } else {
                std.debug.print("[INFO] Fetching...\n", .{});
                if (utils.getInstalledVersion(allocator)) |ver| {
                    std.debug.print("[INFO] Zig {} is already installed. Run `zigup upgrade` to install the latest version.\n", .{ver});
                    return;
                } else |_| {
                    try installVersion(allocator, "latest");
                }
            }
        }
    } else {
        for (flags.items) |flag_item| {
            if (flag_item) |flag| {
                if (std.mem.eql(u8, flag.name, "version")) {
                    try showZigupVersion(allocator);
                } else {
                    try displayHelp();
                }
            }
        }
    }
}

fn displayHelp() !void {
    const usage_str =
        \\ sudo zigup [COMMAND] [OPTIONS...]
        \\
        \\ COMMANDS
        \\  upgrade       Upgrade to zig latest stable version
        \\  install       Install zig with --version or default (latest) 
        \\ 
        \\ OPTIONS
        \\  --version     Choose specific version (e.g. 0.14.0)
        \\
        \\ FLAGS
        \\  --version     Display zig current version
        \\  --help        Display this help message
        \\
    ;
    try stdout.print("Usage:{s}\n", .{usage_str});
}

fn showZigupVersion(allocator: std.mem.Allocator) !void {
    try stdout.print("zig: {}\n", .{try utils.getInstalledVersion(allocator)});
    try stdout.print("zigup: {s}\n", .{ZIGUP_VERSION});
}

fn installVersion(allocator: std.mem.Allocator, chosen_version: []const u8) !void {
    _ = signal.signal(signal.SIGINT, cleanUp);

    const zig_builds_url = ZIG_WEBSITE ++ DOWNLOAD_PATH;
    const index_file_path = "zig-builds-index.json";
    try downloader.downloadFileWithProgress(allocator, zig_builds_url, index_file_path, false);

    const json_text = try std.fs.cwd().readFileAlloc(allocator, index_file_path, 1 << 16);
    defer allocator.free(json_text);
    defer std.fs.cwd().deleteFile(index_file_path) catch |err| {
        std.debug.print("[ERROR] Error deleting file: {}\n", .{err});
    };

    var parsed = try json.parseFromSlice(json.Value, allocator, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value.object;

    var version_items: ArrayList(VersionItem) = .init(allocator);
    defer version_items.deinit();

    var root_it = root.iterator();
    while (root_it.next()) |entry| {
        const key = entry.key_ptr.*;

        // Skip "master"
        if (std.mem.eql(u8, key, "master")) {
            continue;
        }

        const semver = try std.SemanticVersion.parse(key);
        try version_items.append(.{
            .name = key,
            .semver = semver,
        });
    }

    if (version_items.items.len == 0) {
        std.debug.print("[ERROR] No release versions found.\n", .{});
        return;
    }

    std.sort.insertion(VersionItem, version_items.items, {}, struct {
        fn lessThan(_: void, a: VersionItem, b: VersionItem) bool {
            return std.SemanticVersion.order(a.semver, b.semver) == .lt;
        }
    }.lessThan);

    var required_version: VersionItem = undefined;

    if (std.mem.eql(u8, chosen_version, "latest")) {
        required_version = version_items.items[version_items.items.len - 1];
    } else {
        const chosen_index = indexOfVersion(version_items.items, try VersionItem.parse(chosen_version)) catch {
            std.debug.print("[ERROR] Version not found: {s}\n", .{chosen_version});
            return;
        };
        required_version = version_items.items[chosen_index];
    }

    var installed_version: std.SemanticVersion = undefined;
    if (utils.getInstalledVersion(allocator)) |ver| {
        installed_version = ver;
    } else |_| {
        installed_version = try std.SemanticVersion.parse("0.0.0");
    }

    switch (std.SemanticVersion.order(required_version.semver, installed_version)) {
        .eq => {
            std.debug.print("[INFO] Zig {s} is up to date.\n", .{required_version.name});
            return;
        },
        else => {},
    }

    const latest_data = root.get(required_version.name).?.object;

    const tarball_url = latest_data.get("x86_64-linux").?.object.get("tarball").?.string;
    std.debug.print("[INFO] Downloading zig {s}.\n", .{required_version.name});

    try downloader.downloadFileWithProgress(allocator, tarball_url, "zig-build-latest.tar", true);
    try utils.extractTarball(allocator);

    std.debug.print("[INFO] Installing zig {s}.\n", .{required_version.name});
    try utils.installZig();
    try std.fs.cwd().deleteTree("zig-build-latest");
    try std.fs.cwd().deleteFile("zig-build-latest.tar");
    std.debug.print("[INFO] Zig version {s} installed!\n", .{required_version.name});
}

fn indexOfVersion(slice: []VersionItem, elem: VersionItem) !usize {
    for (slice, 0..) |el, idx| {
        if (std.SemanticVersion.order(el.semver, elem.semver) == .eq) {
            return idx;
        }
    }
    return error.IndexNotFound;
}

pub const VersionItem = struct {
    name: []const u8,
    semver: std.SemanticVersion,

    pub fn parse(version_str: []const u8) !VersionItem {
        return .{
            .name = version_str,
            .semver = try std.SemanticVersion.parse(version_str),
        };
    }
};

fn cleanUp(_: c_int) callconv(.c) void {
    std.fs.cwd().deleteFile("zig-build-latest") catch {};
    std.fs.cwd().deleteFile("zig-build-latest.tar") catch {};
    std.fs.cwd().deleteFile("zig-builds-index.json") catch {};
    std.process.exit(0);
}
