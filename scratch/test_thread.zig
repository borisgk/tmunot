const std = @import("std");

pub fn main() !void {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{
        .async_limit = .unlimited,
    });
    defer threaded.deinit();
    const io = threaded.io();

    var buf: [256]u8 = undefined;
    const socket: std.Io.net.Socket = undefined;
    const stream = std.Io.net.Stream{ .socket = socket };
    var writer = stream.writer(io, &buf);
    
    // Test that interface flush compiles
    _ = writer.interface.flush() catch {};
    std.debug.print("interface flush compiles!\n", .{});
}
