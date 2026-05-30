const std = @import("std");

const FfprobeStream = struct {
    width: ?i32 = null,
    height: ?i32 = null,
    side_data_list: ?[]struct {
        rotation: ?i32 = null,
    } = null,
};
const FfprobeFormat = struct {
    tags: ?struct {
        creation_time: ?[]const u8 = null,
    } = null,
};
const FfprobeResult = struct {
    streams: ?[]FfprobeStream = null,
    format: ?FfprobeFormat = null,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const mock_json =
        \\{
        \\    "streams": [
        \\        {
        \\            "width": 1920,
        \\            "height": 1080,
        \\            "side_data_list": [
        \\                {
        \\                    "side_data_type": "Display Matrix",
        \\                    "rotation": -90
        \\                }
        \\            ]
        \\        }
        \\    ],
        \\    "format": {
        \\        "tags": {
        \\            "creation_time": "2024-10-21T12:30:22.000000Z"
        \\        }
        \\    }
        \\}
    ;

    const parsed = try std.json.parseFromSlice(FfprobeResult, allocator, mock_json, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const res = parsed.value;
    if (res.streams) |streams| {
        if (streams.len > 0) {
            var w = streams[0].width orelse 0;
            var h = streams[0].height orelse 0;
            var rot: i32 = 0;
            if (streams[0].side_data_list) |sdl| {
                if (sdl.len > 0) {
                    rot = sdl[0].rotation orelse 0;
                }
            }
            if (rot == 90 or rot == -90 or rot == 270 or rot == -270) {
                const temp = w;
                w = h;
                h = temp;
            }
            std.debug.print("Dimensions: {d}x{d} (rotation: {d})\n", .{w, h, rot});
        }
    }

    if (res.format) |fmt| {
        if (fmt.tags) |tags| {
            if (tags.creation_time) |ct| {
                std.debug.print("Creation time: {s}\n", .{ct});
                // Convert ISO8601 "YYYY-MM-DDTHH:MM:SS.xxxxxxZ" to "YYYY-MM-DD HH:MM:SS"
                if (ct.len >= 19) {
                    var date_buf: [19]u8 = undefined;
                    @memcpy(date_buf[0..10], ct[0..10]);
                    date_buf[10] = ' ';
                    @memcpy(date_buf[11..19], ct[11..19]);
                    std.debug.print("Formatted shooting date: {s}\n", .{date_buf});
                }
            }
        }
    }
}
