const std = @import("std");

pub const timeval = extern struct {
    tv_sec: c_long,
    tv_usec: c_long,
};
pub extern "c" fn gettimeofday(tv: *timeval, tz: ?*anyopaque) c_int;

pub const timespec = extern struct {
    tv_sec: c_long,
    tv_nsec: c_long,
};
pub extern "c" fn clock_gettime(clk_id: c_int, tp: *timespec) c_int;
pub const CLOCK_THREAD_CPUTIME_ID: c_int = 3;

pub fn getWallMillis() f64 {
    var tv: timeval = undefined;
    _ = gettimeofday(&tv, null);
    return @as(f64, @floatFromInt(tv.tv_sec)) * 1000.0 + @as(f64, @floatFromInt(tv.tv_usec)) / 1000.0;
}

pub fn getThreadCpuMillis() f64 {
    var ts: timespec = undefined;
    _ = clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts);
    return @as(f64, @floatFromInt(ts.tv_sec)) * 1000.0 + @as(f64, @floatFromInt(ts.tv_nsec)) / 1000000.0;
}

pub const VipsImage = opaque {};

pub extern fn vips_init(argv0: [*c]const u8) c_int;
pub extern fn vips_shutdown() void;
pub extern fn vips_error_buffer() [*c]const u8;
pub extern fn g_object_unref(object: ?*anyopaque) void;

pub extern fn vips_thumbnail(
    filename: [*c]const u8,
    out: *?*VipsImage,
    width: c_int,
    ...
) c_int;

pub extern fn vips_thumbnail_image(
    in: ?*VipsImage,
    out: *?*VipsImage,
    width: c_int,
    ...
) c_int;

pub extern fn vips_image_copy_memory(
    in: ?*VipsImage,
) ?*VipsImage;

pub extern fn vips_image_write_to_file(
    in: ?*VipsImage,
    name: [*c]const u8,
    ...
) c_int;

pub extern fn mkdir(pathname: [*c]const u8, mode: c_uint) c_int;

pub extern fn vips_image_new_from_buffer(buf: ?*const anyopaque, len: usize, option_string: [*c]const u8, ...) ?*VipsImage;
pub extern fn vips_thumbnail_buffer(buf: ?*const anyopaque, len: usize, out: *?*VipsImage, width: c_int, ...) c_int;
pub extern fn vips_image_get_width(image: ?*VipsImage) c_int;
pub extern fn vips_image_get_height(image: ?*VipsImage) c_int;
