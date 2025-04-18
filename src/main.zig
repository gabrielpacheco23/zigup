const std = @import("std");
const builtin = @import("builtin");
const json = std.json;
const ArrayList = std.ArrayList;

const utils = @import("utils.zig");
const downloader = @import("downloader.zig");

const stdout = std.io.getStdOut().writer();
const ZIG_WEBSITE: []const u8 = "https://ziglang.org";
const DOWNLOAD_PATH: []const u8 = "/download/index.json";

// TODO: MAKE INSTALLING `ZLS` TOO
// COMMANDS: git clone https://github.com/zigtools/zls
//           cd zls
//           git checkout 0.14.0
//           zig build -Doptimize=ReleaseSafe

pub fn main() !void {
    var dba: std.heap.DebugAllocator(.{}) = .init;
    defer _ = dba.deinit();
    const allocator = dba.allocator();

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

    // Create a list to store version items
    var version_items: ArrayList(VersionItem) = .init(allocator);
    defer version_items.deinit();

    // Iterate through keys in the root object and store them
    var root_it = root.iterator();
    while (root_it.next()) |entry| {
        const key = entry.key_ptr.*;

        // Skip "master"
        if (std.mem.eql(u8, key, "master")) {
            continue;
        }

        // Parse the version string
        const semver = try std.SemanticVersion.parse(key);
        try version_items.append(.{
            .name = key,
            .semver = semver,
        });
    }

    // No versions available
    if (version_items.items.len == 0) {
        std.debug.print("No release versions found.\n", .{});
        return;
    }

    // Sort versions using semantic version comparison
    std.sort.insertion(VersionItem, version_items.items, {}, struct {
        fn lessThan(_: void, a: VersionItem, b: VersionItem) bool {
            // Compare using semantic versioning (descending order)
            return std.SemanticVersion.order(a.semver, b.semver) == .lt;
        }
    }.lessThan);

    // Get the latest version (first after sorting)
    const latest_version = version_items.items[version_items.items.len - 1];
    const installed_version = utils.getInstalledVersion(allocator) catch {
        std.debug.print("[INFO] Zig is not installed on this machine.\n", .{});
        std.debug.print("[INFO] Run `zig-up install` to install the latest version.\n", .{});
        return;
    };

    switch (std.SemanticVersion.order(latest_version.semver, installed_version)) {
        .lt, .eq => {
            std.debug.print("Zig {s} is up to date!\n", .{latest_version.name});
            return;
        },
        .gt => {
            std.debug.print("There is a new zig version available: {s}.\n", .{latest_version.name});
        },
    }

    const latest_data = root.get(latest_version.name).?.object;

    const tarball_url = latest_data.get("x86_64-linux").?.object.get("tarball").?.string;
    std.debug.print("[INFO] Downloading zig {s}.\n", .{latest_version.name});

    try downloader.downloadFileWithProgress(allocator, tarball_url, "zig-build-latest.tar", true);
    try utils.extractTarball(allocator);
    // try utils.extractTarFile(allocator, "zig-build-latest.tar", "zig-build-latest");

    std.debug.print("[INFO] Installing zig {s}.\n", .{latest_version.name});
    try utils.installZig();
    try std.fs.cwd().deleteTree("zig-build-latest");
    try std.fs.cwd().deleteFile("zig-build-latest.tar");
    std.debug.print("Zig version {s} installed!\n", .{latest_version.name});
}

pub const VersionItem = struct {
    name: []const u8,
    semver: std.SemanticVersion,
};
