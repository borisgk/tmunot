const std = @import("std");

pub const ExifEntry = extern struct {
    tag: c_int,
    format: c_int,
    components: c_ulong,
    data: ?[*]u8,
    size: c_uint,
    parent: ?*anyopaque,
    priv: ?*anyopaque,
};

pub extern "c" fn exif_data_new_from_file(path: [*c]const u8) ?*anyopaque;
pub extern "c" fn exif_data_unref(data: ?*anyopaque) void;
pub extern "c" fn exif_content_get_entry(content: ?*anyopaque, tag: c_int) ?*ExifEntry;
pub extern "c" fn exif_entry_get_value(entry: ?*ExifEntry, val: [*c]u8, maxlen: c_uint) [*c]u8;

pub fn main() !void {
    const data = exif_data_new_from_file("photos/admin/originals/2026/ 5/4b24ef80-e1ea-4e1a-acf6-209a721da309.jpg");
    if (data == null) {
        std.debug.print("Failed to open EXIF\n", .{});
        return;
    }
    defer exif_data_unref(data);

    // we don't have the struct definition, let's just do a hacky run of the existing `extractFullExifFromBuffer`
}
