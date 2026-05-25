const std = @import("std");

pub const ExifTag = c_int;
pub const ExifFormat = c_int;
pub const ExifIfd = c_int;

pub const ExifEntry = extern struct {
    tag: ExifTag,
    format: ExifFormat,
    components: c_ulong,
    data: ?[*]u8,
    size: c_uint,
    parent: ?*ExifContent,
    priv: ?*anyopaque,
};

pub const ExifContent = extern struct {
    entries: ?[*]?*ExifEntry,
    count: c_uint,
    parent: ?*anyopaque,
    priv: ?*anyopaque,
};

pub const ExifData = extern struct {
    ifd: [5]?*ExifContent,
    data: ?[*]u8,
    size: c_uint,
    priv: ?*anyopaque,
};

pub extern "c" fn exif_data_new_from_file(path: [*c]const u8) ?*ExifData;
pub extern "c" fn exif_data_unref(data: ?*ExifData) void;
pub extern "c" fn exif_tag_get_name(tag: ExifTag) [*c]const u8;
pub extern "c" fn exif_tag_get_title(tag: ExifTag) [*c]const u8;
pub extern "c" fn exif_tag_get_description(tag: ExifTag) [*c]const u8;
pub extern "c" fn exif_entry_get_value(entry: ?*ExifEntry, val: [*c]u8, maxlen: c_uint) [*c]u8;
pub extern "c" fn exif_ifd_get_name(ifd: ExifIfd) [*c]const u8;

fn escapeJsonString(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var list = std.ArrayList(u8).empty;
    errdefer list.deinit(allocator);
    
    for (input) |c| {
        switch (c) {
            '\\' => try list.appendSlice(allocator, "\\\\"),
            '"' => try list.appendSlice(allocator, "\\\""),
            '\n' => try list.appendSlice(allocator, "\\n"),
            '\r' => try list.appendSlice(allocator, "\\r"),
            '\t' => try list.appendSlice(allocator, "\\t"),
            else => {
                if (c < 32 or c >= 127) {
                    var hex_seq = [6]u8{ '\\', 'u', '0', '0', 0, 0 };
                    const hex_chars = "0123456789abcdef";
                    hex_seq[4] = hex_chars[c >> 4];
                    hex_seq[5] = hex_chars[c & 0x0f];
                    try list.appendSlice(allocator, &hex_seq);
                } else {
                    try list.append(allocator, c);
                }
            }
        }
    }
    return list.toOwnedSlice(allocator);
}

pub fn extractExifAndSave(allocator: std.mem.Allocator, io: std.Io, image_path: []const u8, json_path: []const u8) !void {
    const image_path_c = try std.fmt.allocPrintSentinel(allocator, "{s}", .{image_path}, 0);
    defer allocator.free(image_path_c);

    const data = exif_data_new_from_file(image_path_c.ptr);
    if (data == null) {
        // Create an empty json file or simple status
        const cwd = std.Io.Dir.cwd();
        var file = try cwd.createFile(io, json_path, .{});
        defer file.close(io);
        var writer = file.writer(io, &.{});
        try writer.interface.writeAll("{}");
        return;
    }
    defer exif_data_unref(data);

    var json_list = std.ArrayList(u8).empty;
    defer json_list.deinit(allocator);

    try json_list.appendSlice(allocator, "{\n");

    var first_ifd = true;
    var ifd: c_int = 0;
    while (ifd < 5) : (ifd += 1) {
        const content = data.?.ifd[@intCast(ifd)];
        if (content) |c| {
            if (c.count > 0 and c.entries != null) {
                const ifd_name = std.mem.span(exif_ifd_get_name(ifd));
                const escaped_ifd = try escapeJsonString(allocator, ifd_name);
                defer allocator.free(escaped_ifd);

                var has_valid_entries = false;
                var check_i: usize = 0;
                while (check_i < c.count) : (check_i += 1) {
                    if (c.entries.?[check_i]) |_| {
                        has_valid_entries = true;
                        break;
                    }
                }

                if (!has_valid_entries) continue;

                if (!first_ifd) {
                    try json_list.appendSlice(allocator, ",\n");
                }
                first_ifd = false;

                try json_list.appendSlice(allocator, "  \"");
                try json_list.appendSlice(allocator, escaped_ifd);
                try json_list.appendSlice(allocator, "\": {\n");

                var first_entry = true;
                var i: usize = 0;
                while (i < c.count) : (i += 1) {
                    if (c.entries.?[i]) |entry| {
                        const tag_name = std.mem.span(exif_tag_get_name(entry.tag));
                        const escaped_tag = try escapeJsonString(allocator, tag_name);
                        defer allocator.free(escaped_tag);

                        var value_buf: [2048]u8 = undefined;
                        _ = exif_entry_get_value(entry, &value_buf, value_buf.len);
                        const val_len = std.mem.indexOfScalar(u8, &value_buf, 0) orelse value_buf.len;
                        const val_str = value_buf[0..val_len];
                        const escaped_val = try escapeJsonString(allocator, val_str);
                        defer allocator.free(escaped_val);

                        if (!first_entry) {
                            try json_list.appendSlice(allocator, ",\n");
                        }
                        first_entry = false;

                        try json_list.appendSlice(allocator, "    \"");
                        try json_list.appendSlice(allocator, escaped_tag);
                        try json_list.appendSlice(allocator, "\": \"");
                        try json_list.appendSlice(allocator, escaped_val);
                        try json_list.appendSlice(allocator, "\"");
                    }
                }
                try json_list.appendSlice(allocator, "\n  }");
            }
        }
    }

    try json_list.appendSlice(allocator, "\n}\n");

    const cwd = std.Io.Dir.cwd();
    var file = try cwd.createFile(io, json_path, .{});
    defer file.close(io);
    var writer = file.writer(io, &.{});
    try writer.interface.writeAll(json_list.items);
}
