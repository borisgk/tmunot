const std = @import("std");

pub extern fn vips_init(argv0: [*c]const u8) c_int;
pub extern fn vips_thumbnail(filename: [*c]const u8, out: *?*anyopaque, width: c_int, ...) c_int;
pub extern fn vips_image_write_to_file(image: *anyopaque, name: [*c]const u8, ...) c_int;

pub fn main() !void {
    _ = vips_init("test");
    var img: ?*anyopaque = null;
    const res = vips_thumbnail("DSC_0086.JPG", &img, 800, "height", @as(c_int, 800), @as(?*anyopaque, null));
    std.debug.print("res = {}\n", .{res});
}
