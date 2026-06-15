const std = @import("std");
const db = @import("db.zig");

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

pub extern "c" fn exif_data_new_from_data(data: [*c]const u8, size: c_uint) ?*ExifData;
pub extern "c" fn exif_data_new_from_file(path: [*c]const u8) ?*ExifData;
pub extern "c" fn exif_data_unref(data: ?*ExifData) void;
pub extern "c" fn exif_tag_get_name(tag: ExifTag) [*c]const u8;
pub extern "c" fn exif_tag_get_name_in_ifd(tag: ExifTag, ifd: ExifIfd) [*c]const u8;
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


pub const ExifMetadata = struct {
    shooting_date: ?[]const u8, // YYYY-MM-DD HH:MM:SS
    width: ?i32,
    height: ?i32,
};

pub fn extractExifFromBuffer(allocator: std.mem.Allocator, buffer: []const u8) !ExifMetadata {
    const data = exif_data_new_from_data(buffer.ptr, @intCast(buffer.len));
    if (data == null) {
        return ExifMetadata{
            .shooting_date = null,
            .width = null,
            .height = null,
        };
    }
    defer exif_data_unref(data);

    var shooting_date: ?[]const u8 = null;
    var width: ?i32 = null;
    var height: ?i32 = null;
    var swap_dimensions = false;

    var ifd: c_int = 0;
    while (ifd < 5) : (ifd += 1) {
        const content = data.?.ifd[@intCast(ifd)];
        if (content) |c| {
            if (c.count > 0 and c.entries != null) {
                var i: usize = 0;
                while (i < c.count) : (i += 1) {
                    if (c.entries.?[i]) |entry| {
                        const tag_name_c = exif_tag_get_name_in_ifd(entry.tag, @intCast(ifd));
                        if (tag_name_c == null) continue;
                        const tag_name = std.mem.span(tag_name_c);

                        var value_buf: [256]u8 = undefined;
                        _ = exif_entry_get_value(entry, &value_buf, value_buf.len);
                        const val_len = std.mem.indexOfScalar(u8, &value_buf, 0) orelse value_buf.len;
                        const val_str = value_buf[0..val_len];

                        if (std.mem.eql(u8, tag_name, "DateTimeOriginal") or (shooting_date == null and std.mem.eql(u8, tag_name, "DateTime"))) {
                            // EXIF DateTime format is usually "YYYY:MM:DD HH:MM:SS"
                            // Convert to ISO8601 "YYYY-MM-DD HH:MM:SS"
                            if (val_str.len >= 19) {
                                var iso_date = try allocator.alloc(u8, 19);
                                @memcpy(iso_date, val_str[0..19]);
                                if (iso_date[4] == ':') iso_date[4] = '-';
                                if (iso_date[7] == ':') iso_date[7] = '-';
                                shooting_date = iso_date;
                            }
                        } else if (std.mem.eql(u8, tag_name, "PixelXDimension") or (width == null and std.mem.eql(u8, tag_name, "ImageWidth"))) {
                            width = std.fmt.parseInt(i32, val_str, 10) catch null;
                        } else if (std.mem.eql(u8, tag_name, "PixelYDimension") or (height == null and std.mem.eql(u8, tag_name, "ImageLength"))) {
                            height = std.fmt.parseInt(i32, val_str, 10) catch null;
                        } else if (std.mem.eql(u8, tag_name, "Orientation")) {
                            if (std.mem.startsWith(u8, val_str, "Left-") or std.mem.startsWith(u8, val_str, "Right-")) {
                                swap_dimensions = true;
                            }
                        }
                    }
                }
            }
        }
    }

    if (swap_dimensions) {
        const temp = width;
        width = height;
        height = temp;
    }

    return ExifMetadata{
        .shooting_date = shooting_date,
        .width = width,
        .height = height,
    };
}

pub fn extractFullExifFromBuffer(allocator: std.mem.Allocator, buffer: []const u8, uuid: []const u8) !db.PhotoExifRecord {
    @setEvalBranchQuota(10000);
    var record = db.PhotoExifRecord{
        .uuid = try allocator.dupe(u8, uuid),
    };

    const data = exif_data_new_from_data(buffer.ptr, @intCast(buffer.len));
    if (data == null) {
        return record;
    }
    defer exif_data_unref(data);

    var ifd: c_int = 0;
    while (ifd < 5) : (ifd += 1) {
        const content = data.?.ifd[@intCast(ifd)];
        if (content) |c| {
            if (c.count > 0 and c.entries != null) {
                var i: usize = 0;
                while (i < c.count) : (i += 1) {
                    if (c.entries.?[i]) |entry| {
                        const tag_name_c = exif_tag_get_name_in_ifd(entry.tag, @intCast(ifd));
                        if (tag_name_c == null) continue;
                        const tag_name = std.mem.span(tag_name_c);

                        var value_buf: [2048]u8 = undefined;
                        _ = exif_entry_get_value(entry, &value_buf, value_buf.len);
                        const val_len = std.mem.indexOfScalar(u8, &value_buf, 0) orelse value_buf.len;
                        if (val_len == 0) continue;
                        const val_str = value_buf[0..val_len];

                        inline for (comptime std.meta.fieldNames(db.PhotoExifRecord)) |field_name| {
                            if (!comptime std.mem.eql(u8, field_name, "uuid")) {
                                if (std.mem.eql(u8, tag_name, field_name)) {
                                    if (@field(record, field_name) == null) {
                                        var final_val = try allocator.dupe(u8, val_str);
                                        
                                        // SQLite compatible Date/Time conversion (YYYY:MM:DD -> YYYY-MM-DD)
                                        if (comptime std.mem.eql(u8, field_name, "DateTime") or 
                                            std.mem.eql(u8, field_name, "DateTimeOriginal") or 
                                            std.mem.eql(u8, field_name, "DateTimeDigitized") or
                                            std.mem.eql(u8, field_name, "GPSDateStamp")) 
                                        {
                                            if (final_val.len >= 10) {
                                                if (final_val[4] == ':') final_val[4] = '-';
                                                if (final_val[7] == ':') final_val[7] = '-';
                                            }
                                        }
                                        @field(record, field_name) = final_val;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return record;
}

