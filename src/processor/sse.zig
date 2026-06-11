const std = @import("std");
const vips = @import("../vips.zig");
const logger = @import("../logger.zig");
const db = @import("../db.zig");
const exif = @import("../exif.zig");
const config_mod = @import("../config.zig");

const queue = @import("queue.zig");
// SSE Connection state
pub const SseClient = struct {
    stream: std.Io.net.Stream,
    username: []const u8,
};

var sse_mutex: std.atomic.Mutex = .unlocked;
var sse_clients = std.ArrayList(SseClient).empty;
var sse_allocator: ?std.mem.Allocator = null;

pub fn initSse(allocator: std.mem.Allocator) void {
    while (!sse_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    sse_allocator = allocator;
    sse_clients = std.ArrayList(SseClient).empty;
    sse_mutex.unlock();
}

pub fn addSseClient(stream: std.Io.net.Stream, username: []const u8) !void {
    while (!sse_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer sse_mutex.unlock();

    const alloc = sse_allocator orelse return error.RegistryNotInitialized;
    try sse_clients.append(alloc, .{
        .stream = stream,
        .username = try alloc.dupe(u8, username),
    });
    std.debug.print("Added SSE client for user: {s}, count: {d}\n", .{ username, sse_clients.items.len });
}

pub fn removeSseClient(stream: std.Io.net.Stream) void {
    while (!sse_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer sse_mutex.unlock();

    const alloc = sse_allocator orelse return;
    var i: usize = 0;
    while (i < sse_clients.items.len) {
        if (sse_clients.items[i].stream.socket.handle == stream.socket.handle) {
            const client = sse_clients.orderedRemove(i);
            alloc.free(client.username);
            std.debug.print("Removed SSE client, remaining count: {d}\n", .{ sse_clients.items.len });
        } else {
            i += 1;
        }
    }
}

pub fn broadcastSseEvent(uuid: []const u8, status: []const u8, ext: []const u8, target_user: []const u8) void {
    while (!sse_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer sse_mutex.unlock();

    const io = queue.global_io orelse return;
    const alloc = sse_allocator orelse return;

    const payload = std.fmt.allocPrint(alloc,
        "data: {{\"uuid\":\"{s}\",\"status\":\"{s}\",\"ext\":\"{s}\"}}\n\n",
        .{ uuid, status, ext }
    ) catch return;
    defer alloc.free(payload);

    var i: usize = 0;
    while (i < sse_clients.items.len) {
        const client = sse_clients.items[i];
        if (std.mem.eql(u8, client.username, target_user)) {
            var write_buf: [256]u8 = undefined;
            var writer = client.stream.writer(io, &write_buf);
            writer.interface.writeAll(payload) catch {
                const removed = sse_clients.orderedRemove(i);
                alloc.free(removed.username);
                removed.stream.close(io);
                continue;
            };
            writer.interface.flush() catch {
                const removed = sse_clients.orderedRemove(i);
                alloc.free(removed.username);
                removed.stream.close(io);
                continue;
            };
        }
        i += 1;
    }
}

pub fn writeKeepAlive(stream: std.Io.net.Stream) !bool {
    while (!sse_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer sse_mutex.unlock();

    const io = queue.global_io orelse return false;
    var write_buf: [256]u8 = undefined;
    var writer = stream.writer(io, &write_buf);
    writer.interface.writeAll(": keep-alive\n\n") catch {
        return false;
    };
    writer.interface.flush() catch {
        return false;
    };
    return true;
}
