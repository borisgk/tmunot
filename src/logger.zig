const std = @import("std");

pub extern "c" fn fopen(pathname: [*c]const u8, mode: [*c]const u8) ?*anyopaque;
pub extern "c" fn fprintf(stream: ?*anyopaque, format: [*c]const u8, ...) c_int;
pub extern "c" fn fclose(stream: ?*anyopaque) c_int;
pub extern "c" fn fflush(stream: ?*anyopaque) c_int;

pub extern "c" fn printf(format: [*c]const u8, ...) c_int;

var log_mutex: std.atomic.Mutex = .unlocked;

pub fn logEvent(uuid: []const u8, event_name: []const u8, t_start: f64, t_event: f64) void {
    while (!log_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer log_mutex.unlock();

    const elapsed = t_event - t_start;

    // Output to terminal (using stdout C printf and fflush to guarantee terminal visibility)
    _ = printf(
        "[DEBUG] [%.*s] Event '%.*s' at wall-clock %.3f ms (elapsed: %.3f ms)\n",
        @as(c_int, @intCast(uuid.len)),
        uuid.ptr,
        @as(c_int, @intCast(event_name.len)),
        event_name.ptr,
        t_event,
        elapsed,
    );
    _ = fflush(null);

    // Also output to terminal using stderr / debug print as backup
    std.debug.print("[DEBUG] [{s}] Event '{s}' at wall-clock {d:.3} ms (elapsed: {d:.3} ms)\n", .{
        uuid,
        event_name,
        t_event,
        elapsed,
    });

    // Output to debug log file
    const file_ptr = fopen("upload_debug.log", "a");
    if (file_ptr) |f| {
        defer _ = fclose(f);
        _ = fprintf(
            f,
            "[DEBUG] [%.*s] Event '%.*s' at wall-clock %.3f ms (elapsed: %.3f ms)\n",
            @as(c_int, @intCast(uuid.len)),
            uuid.ptr,
            @as(c_int, @intCast(event_name.len)),
            event_name.ptr,
            t_event,
            elapsed,
        );
        _ = fflush(f);
    }
}
