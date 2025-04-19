const std = @import("std");
const http = std.http;
const fs = std.fs;
const io = std.io;
const Allocator = std.mem.Allocator;
const time = std.time;

const ProgressInfo = struct {
    total_size: ?usize = null,
    bytes_downloaded: usize = 0,
    last_update_time: i128 = 0,
    update_interval_ns: i64 = 250 * time.ns_per_ms, // 250ms between updates
};

pub fn downloadFileWithProgress(allocator: Allocator, url_str: []const u8, output_path: []const u8, should_display: bool) !void {
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(url_str);

    const file = try fs.cwd().createFile(output_path, .{});
    defer file.close();

    var server_header_buffer: [8192]u8 = undefined;

    var req = try client.open(.GET, uri, .{
        .server_header_buffer = &server_header_buffer,
    });
    defer req.deinit();

    try req.send();
    try req.wait();

    if (req.response.status != .ok) {
        std.debug.print("HTTP request failed with status: {}\n", .{req.response.status});
        return error.HttpRequestFailed;
    }

    var progress = ProgressInfo{
        .last_update_time = time.nanoTimestamp(),
    };

    if (req.response.content_length) |length| {
        progress.total_size = length;
    }

    const reader = req.reader();
    var buffer: [8192]u8 = undefined;

    while (true) {
        const bytes_read = try reader.read(&buffer);
        if (bytes_read == 0) break;

        try file.writeAll(buffer[0..bytes_read]);

        progress.bytes_downloaded += bytes_read;

        if (should_display) {
            const current_time = time.nanoTimestamp();
            if (current_time - progress.last_update_time >= progress.update_interval_ns) {
                try displayProgress(&progress);
                progress.last_update_time = current_time;
            }
        }
    }

    if (should_display) {
        try displayProgress(&progress);
        std.debug.print("\n", .{});
    }
}

pub fn displayProgress(progress: *const ProgressInfo) !void {
    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    try stdout.writeAll("\r");

    if (progress.total_size) |total| {
        const percentage = @as(f64, @floatFromInt(progress.bytes_downloaded)) / @as(f64, @floatFromInt(total)) * 100.0;
        const mb_downloaded = @as(f64, @floatFromInt(progress.bytes_downloaded)) / 1_048_576.0;
        const mb_total = @as(f64, @floatFromInt(total)) / 1_048_576.0;

        const bar_width = 30;
        const filled_width = @min(bar_width, @as(usize, @intFromFloat((percentage / 100.0) * @as(f64, @floatFromInt(bar_width)))));

        try stdout.writeAll("[");
        var i: usize = 0;
        while (i < filled_width) : (i += 1) {
            try stdout.writeAll("=");
        }
        if (filled_width < bar_width) {
            try stdout.writeAll(">");
            i += 1;
        }
        while (i < bar_width) : (i += 1) {
            try stdout.writeAll(" ");
        }
        try stdout.writeAll("]");

        try stdout.print(" {d:.1}% ({d:.2} MB / {d:.2} MB)", .{ percentage, mb_downloaded, mb_total });
    } else {
        // No content length available, just show bytes downloaded
        const mb_downloaded = @as(f64, @floatFromInt(progress.bytes_downloaded)) / 1_048_576.0;
        try stdout.print("Downloaded: {d:.2} MB\n", .{mb_downloaded});
    }
}
