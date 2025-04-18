const std = @import("std");

pub fn installZig() !void {
    const old_path = "zig-build-latest/";

    const new_bin_dir = try std.fs.openDirAbsolute("/usr/bin", .{ .access_sub_paths = true });
    std.fs.rename(std.fs.cwd(), old_path ++ "zig", new_bin_dir, "zig") catch |err| {
        std.debug.print("[ERROR]: Error moving zig bin: {}\n", .{err});
        std.process.exit(0);
    };

    // std.debug.print("Success moving zig bin to /usr/bin/zig.\n", .{});

    const new_lib_dir = try std.fs.openDirAbsolute("/usr/lib", .{ .access_sub_paths = true });
    std.fs.rename(std.fs.cwd(), old_path ++ "lib", new_lib_dir, "zig") catch |err| {
        switch (err) {
            error.PathAlreadyExists => {
                try std.fs.deleteTreeAbsolute("/usr/lib/zig");
                try std.fs.rename(std.fs.cwd(), old_path ++ "lib", new_lib_dir, "zig");
            },
            else => {
                std.debug.print("[ERROR]: Error moving zig lib: {}\n", .{err});
                std.process.exit(0);
            },
        }
    };

    // std.debug.print("Success moving zig lib to /usr/lib/zig.\n", .{});
}

//
pub fn getInstalledVersion(allocator: std.mem.Allocator) !std.SemanticVersion {
    const args = [_][]const u8{ "zig", "version" };

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &args,
    });

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const versionStr = std.mem.trim(u8, result.stdout, &[_]u8{'\n'});
    return try std.SemanticVersion.parse(versionStr);
}

// WARNING: TOO SLOW FOR NOW (std.tar)
pub fn extractTarSlow(allocator: std.mem.Allocator, file_path: []const u8, out_path: []const u8) !void {
    var _file = try std.fs.cwd().openFile(file_path, .{});
    var buffered_reader = std.io.bufferedReader(_file.reader());
    var decompressed = try std.compress.xz.decompress(allocator, buffered_reader.reader());
    defer decompressed.deinit();

    try std.fs.cwd().makeDir(out_path);

    const out_dir = try std.fs.cwd().openDir(out_path, .{});

    try std.tar.pipeToFileSystem(out_dir, decompressed.reader(), .{
        .strip_components = 1,
        .mode_mode = .ignore,
        // .exclude_empty_directories = true,
    });

    std.debug.print("[INFO] Extracted .tar file: {s}.\n", .{out_path});
}

pub fn extractTarball(allocator: std.mem.Allocator) !void {
    try std.fs.cwd().makeDir("zig-build-latest");

    const args = [_][]const u8{
        "tar",
        "-xvf",
        "zig-build-latest.tar",
        "-C",
        "zig-build-latest",
        "--strip-components=1",
    };

    try execCmd(allocator, args);
    std.debug.print("[INFO] Extracted .tar file.\n", .{});
}

fn execCmd(allocator: std.mem.Allocator, args: [6][]const u8) !void {
    var child_proc = std.process.Child.init(&args, allocator);
    child_proc.stdin_behavior = .Ignore;
    child_proc.stdout_behavior = .Ignore;
    child_proc.stderr_behavior = .Ignore;
    _ = try child_proc.spawnAndWait();
}
