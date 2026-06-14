// write_queue.zig
// Routes DB write operations that originate from OS worker threads through a FIFO queue
// that is drained by the main async fiber context. This ensures all SQLite calls happen
// from the same io context that holds core.db_mutex, eliminating SQLITE_BUSY errors.

const std = @import("std");
const core = @import("core.zig");
const photos_mod = @import("photos.zig");

// ---- Job payload types -------------------------------------------------

/// Owned copy of a PhotoRecord (all slices allocated from global_allocator).
pub const OwnedPhotoRecord = struct {
    uuid: []const u8,
    username: []const u8,
    filename: []const u8,
    extension: []const u8,
    year: []const u8,
    month: []const u8,
    day: []const u8,
    shooting_date: ?[]const u8,
    upload_date: []const u8,
    width: ?i32,
    height: ?i32,

    pub fn deinit(self: OwnedPhotoRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.uuid);
        allocator.free(self.username);
        allocator.free(self.filename);
        allocator.free(self.extension);
        allocator.free(self.year);
        allocator.free(self.month);
        allocator.free(self.day);
        if (self.shooting_date) |sd| allocator.free(sd);
        allocator.free(self.upload_date);
    }
};

/// Owned copy of a PhotoExifRecord with its associated username.
pub const OwnedPhotoExif = struct {
    username: []const u8,
    record: photos_mod.PhotoExifRecord,

    pub fn deinit(self: OwnedPhotoExif, allocator: std.mem.Allocator) void {
        allocator.free(self.username);
        @setEvalBranchQuota(10000);
        inline for (comptime std.meta.fieldNames(photos_mod.PhotoExifRecord)) |field_name| {
            // uuid is a non-optional []const u8; all other fields are ?[]const u8
            if (comptime std.mem.eql(u8, field_name, "uuid")) {
                allocator.free(self.record.uuid);
            } else {
                if (@field(self.record, field_name)) |v| allocator.free(v);
            }
        }
    }
};

/// Owned copy of a VideoMetadataRecord with its associated username.
pub const OwnedVideoMeta = struct {
    username: []const u8,
    record: photos_mod.VideoMetadataRecord,

    pub fn deinit(self: OwnedVideoMeta, allocator: std.mem.Allocator) void {
        allocator.free(self.username);
        @setEvalBranchQuota(10000);
        inline for (comptime std.meta.fieldNames(photos_mod.VideoMetadataRecord)) |field_name| {
            if (comptime !std.mem.eql(u8, field_name, "uuid")) {
                if (@field(self.record, field_name)) |v| allocator.free(v);
            }
        }
        allocator.free(self.record.uuid);
    }
};

// ---- Tagged-union job --------------------------------------------------

pub const DbWriteJob = union(enum) {
    insert_photo: OwnedPhotoRecord,
    insert_photo_exif: OwnedPhotoExif,
    insert_video_metadata: OwnedVideoMeta,
};

/// Singly-linked node that wraps a job in the queue.
const Node = struct {
    job: DbWriteJob,
    next: ?*Node = null,
};

// ---- Queue state -------------------------------------------------------

var queue_mutex: std.atomic.Mutex = .unlocked;
var queue_head: ?*Node = null;
var queue_tail: ?*Node = null;
var queue_sem: std.Io.Semaphore = .{};
var drain_started: bool = false;

// ---- Internal helpers --------------------------------------------------

fn enqueue(node: *Node) void {
    while (!queue_mutex.tryLock()) std.atomic.spinLoopHint();
    defer queue_mutex.unlock();

    node.next = null;
    if (queue_tail) |tail| {
        tail.next = node;
        queue_tail = node;
    } else {
        queue_head = node;
        queue_tail = node;
    }
}

fn dequeue() ?*Node {
    while (!queue_mutex.tryLock()) std.atomic.spinLoopHint();
    defer queue_mutex.unlock();

    if (queue_head) |head| {
        queue_head = head.next;
        if (queue_head == null) queue_tail = null;
        return head;
    }
    return null;
}

// ---- Public push API (called from worker OS threads) -------------------

/// Push an insert_photo job. Copies all string fields from `record` into
/// global_allocator so the caller can safely free its own copy immediately after.
pub fn pushInsertPhoto(record: photos_mod.PhotoRecord) !void {
    const alloc = core.global_allocator;
    const io = core.global_io orelse return error.DbNotInitialized;

    const owned = OwnedPhotoRecord{
        .uuid          = try alloc.dupe(u8, record.uuid),
        .username      = try alloc.dupe(u8, record.username),
        .filename      = try alloc.dupe(u8, record.filename),
        .extension     = try alloc.dupe(u8, record.extension),
        .year          = try alloc.dupe(u8, record.year),
        .month         = try alloc.dupe(u8, record.month),
        .day           = try alloc.dupe(u8, record.day),
        .shooting_date = if (record.shooting_date) |sd| try alloc.dupe(u8, sd) else null,
        .upload_date   = try alloc.dupe(u8, record.upload_date),
        .width         = record.width,
        .height        = record.height,
    };

    const node = try alloc.create(Node);
    node.* = .{ .job = .{ .insert_photo = owned } };

    std.debug.print("[DB-QUEUE] push insert_photo uuid={s}\n", .{record.uuid});

    enqueue(node);
    queue_sem.post(io);
}

/// Push an insert_photo_exif job. Copies all fields.
pub fn pushInsertPhotoExif(username: []const u8, record: photos_mod.PhotoExifRecord) !void {
    const alloc = core.global_allocator;
    const io = core.global_io orelse return error.DbNotInitialized;

    var owned_record: photos_mod.PhotoExifRecord = undefined;
    @setEvalBranchQuota(10000);
    inline for (comptime std.meta.fieldNames(photos_mod.PhotoExifRecord)) |field_name| {
        if (comptime std.mem.eql(u8, field_name, "uuid")) {
            // uuid is non-optional []const u8
            @field(owned_record, field_name) = try alloc.dupe(u8, record.uuid);
        } else {
            // all other fields are ?[]const u8
            if (@field(record, field_name)) |v| {
                @field(owned_record, field_name) = try alloc.dupe(u8, v);
            } else {
                @field(owned_record, field_name) = null;
            }
        }
    }

    const owned = OwnedPhotoExif{
        .username = try alloc.dupe(u8, username),
        .record   = owned_record,
    };

    const node = try alloc.create(Node);
    node.* = .{ .job = .{ .insert_photo_exif = owned } };

    std.debug.print("[DB-QUEUE] push insert_photo_exif uuid={s}\n", .{record.uuid});

    enqueue(node);
    queue_sem.post(io);
}

/// Push an insert_video_metadata job. Copies all fields.
pub fn pushInsertVideoMetadata(username: []const u8, record: photos_mod.VideoMetadataRecord) !void {
    const alloc = core.global_allocator;
    const io = core.global_io orelse return error.DbNotInitialized;

    var owned_record: photos_mod.VideoMetadataRecord = undefined;
    @setEvalBranchQuota(10000);
    // uuid is a non-optional []const u8 in VideoMetadataRecord
    owned_record.uuid = try alloc.dupe(u8, record.uuid);
    inline for (comptime std.meta.fieldNames(photos_mod.VideoMetadataRecord)) |field_name| {
        if (comptime std.mem.eql(u8, field_name, "uuid")) continue;
        if (@field(record, field_name)) |v| {
            @field(owned_record, field_name) = try alloc.dupe(u8, v);
        } else {
            @field(owned_record, field_name) = null;
        }
    }

    const owned = OwnedVideoMeta{
        .username = try alloc.dupe(u8, username),
        .record   = owned_record,
    };

    const node = try alloc.create(Node);
    node.* = .{ .job = .{ .insert_video_metadata = owned } };

    std.debug.print("[DB-QUEUE] push insert_video_metadata uuid={s}\n", .{record.uuid});

    enqueue(node);
    queue_sem.post(io);
}

// ---- Drain fiber (runs on the main async io context) -------------------

fn drainLoop(io: std.Io) void {
    std.debug.print("[DB-QUEUE] drain fiber started\n", .{});
    while (true) {
        // Sleep until a job is available
        queue_sem.waitUncancelable(io);

        while (dequeue()) |node| {
            defer core.global_allocator.destroy(node);

            switch (node.job) {
                .insert_photo => |owned| {
                    defer owned.deinit(core.global_allocator);

                    const record = photos_mod.PhotoRecord{
                        .uuid          = owned.uuid,
                        .username      = owned.username,
                        .filename      = owned.filename,
                        .extension     = owned.extension,
                        .year          = owned.year,
                        .month         = owned.month,
                        .day           = owned.day,
                        .shooting_date = owned.shooting_date,
                        .upload_date   = owned.upload_date,
                        .width         = owned.width,
                        .height        = owned.height,
                    };

                    // Import photos DB module to call insertPhoto
                    const photos_db = @import("photos.zig");
                    photos_db.insertPhoto(record) catch |err| {
                        std.debug.print("[DB-QUEUE] drain insert_photo uuid={s} -> ERROR: {}\n", .{ owned.uuid, err });
                        continue;
                    };
                    std.debug.print("[DB-QUEUE] drain insert_photo uuid={s} -> ok\n", .{owned.uuid});
                },

                .insert_photo_exif => |owned| {
                    defer owned.deinit(core.global_allocator);

                    const photos_db = @import("photos.zig");
                    photos_db.insertPhotoExif(owned.username, owned.record) catch |err| {
                        std.debug.print("[DB-QUEUE] drain insert_photo_exif uuid={s} -> ERROR: {}\n", .{ owned.record.uuid, err });
                        continue;
                    };
                    std.debug.print("[DB-QUEUE] drain insert_photo_exif uuid={s} -> ok\n", .{owned.record.uuid});
                },

                .insert_video_metadata => |owned| {
                    defer owned.deinit(core.global_allocator);

                    const photos_db = @import("photos.zig");
                    photos_db.insertVideoMetadata(owned.username, owned.record) catch |err| {
                        std.debug.print("[DB-QUEUE] drain insert_video_metadata uuid={s} -> ERROR: {}\n", .{ owned.record.uuid, err });
                        continue;
                    };
                    std.debug.print("[DB-QUEUE] drain insert_video_metadata uuid={s} -> ok\n", .{owned.record.uuid});
                },
            }
        }
    }
}

/// Start the async drain fiber. Must be called once from the main async context
/// (same `io` that the HTTP server fibers use) before any worker threads are started.
pub fn startDrainFiber(io: std.Io) !void {
    if (drain_started) return;
    drain_started = true;
    std.debug.print("[DB-QUEUE] starting drain fiber\n", .{});
    _ = io.async(drainLoop, .{io});
}
