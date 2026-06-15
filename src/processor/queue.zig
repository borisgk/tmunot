const std = @import("std");
const vips = @import("../vips.zig");
const logger = @import("../logger.zig");
const db = @import("../db.zig");

const config_mod = @import("../config.zig");

const sse = @import("sse.zig");
const media = @import("media.zig");
pub const FileJob = struct {
    allocator: std.mem.Allocator,
    uuid: []const u8,           // Photo UUID
    username: []const u8,       // Username of the owner
    filename: []const u8,       // Original filename
    year: []const u8,           // Chronological year
    month: []const u8,          // Chronological month
    day: []const u8,            // Chronological day
    upload_date: []const u8,    // Date when uploaded
    extension: []const u8,      // Lowercase file extension
    quality: i32,
    t_start: f64,
    next: ?*FileJob = null,
};

// Queue state
var job_queue_mutex: std.atomic.Mutex = .unlocked;
var job_queue_head: ?*FileJob = null;
var job_queue_tail: ?*FileJob = null;
var job_queue_sem = std.Io.Semaphore{};
var worker_threads: ?[]std.Thread = null;
var worker_should_exit: bool = false;
pub var global_io: ?std.Io = null;
pub var global_config: ?*const config_mod.Config = null;

// Registry State
pub const JobStatus = enum {
    pending,
    processing,
};

pub const ActiveJob = struct {
    username: []const u8,
    year: []const u8,
    month: []const u8,
    extension: []const u8,
    status: JobStatus,
};

var registry_mutex: std.atomic.Mutex = .unlocked;
var active_jobs: ?std.StringHashMap(ActiveJob) = null;
var registry_allocator: ?std.mem.Allocator = null;

pub fn initRegistry(allocator: std.mem.Allocator) void {
    while (!registry_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer registry_mutex.unlock();

    if (active_jobs == null) {
        active_jobs = std.StringHashMap(ActiveJob).init(allocator);
        registry_allocator = allocator;
    }
}

pub fn registerJob(uuid: []const u8, username: []const u8, year: []const u8, month: []const u8, extension: []const u8) !void {
    while (!registry_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer registry_mutex.unlock();

    if (active_jobs) |*map| {
        const alloc = registry_allocator orelse return error.RegistryNotInitialized;
        const job = ActiveJob{
            .username = try alloc.dupe(u8, username),
            .year = try alloc.dupe(u8, year),
            .month = try alloc.dupe(u8, month),
            .extension = try alloc.dupe(u8, extension),
            .status = .pending,
        };
        const dupe_uuid = try alloc.dupe(u8, uuid);
        try map.put(dupe_uuid, job);
    }
}

pub fn updateJobStatus(uuid: []const u8, status: JobStatus) void {
    while (!registry_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer registry_mutex.unlock();

    if (active_jobs) |*map| {
        if (map.getPtr(uuid)) |job| {
            job.status = status;
        }
    }
}

pub fn removeJob(uuid: []const u8) void {
    while (!registry_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer registry_mutex.unlock();

    if (active_jobs) |*map| {
        if (map.fetchRemove(uuid)) |kv| {
            const alloc = registry_allocator orelse return;
            alloc.free(kv.key);
            alloc.free(kv.value.username);
            alloc.free(kv.value.year);
            alloc.free(kv.value.month);
            alloc.free(kv.value.extension);
        }
    }
}

pub fn getActiveJob(uuid: []const u8, allocator: std.mem.Allocator) !?ActiveJob {
    while (!registry_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer registry_mutex.unlock();

    if (active_jobs) |map| {
        if (map.get(uuid)) |job| {
            return ActiveJob{
                .username = try allocator.dupe(u8, job.username),
                .year = try allocator.dupe(u8, job.year),
                .month = try allocator.dupe(u8, job.month),
                .extension = try allocator.dupe(u8, job.extension),
                .status = job.status,
            };
        }
    }
    return null;
}

pub fn isJobActive(uuid: []const u8) bool {
    while (!registry_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer registry_mutex.unlock();

    if (active_jobs) |map| {
        return map.contains(uuid);
    }
    return false;
}
pub fn pushJob(job: *FileJob) void {
    while (!job_queue_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }

    job.next = null;
    if (job_queue_tail) |tail| {
        tail.next = job;
        job_queue_tail = job;
    } else {
        job_queue_head = job;
        job_queue_tail = job;
    }
    job_queue_mutex.unlock();

    if (global_io) |io| {
        job_queue_sem.post(io);
    }
}

fn popJob() ?*FileJob {
    while (!job_queue_mutex.tryLock()) {
        std.atomic.spinLoopHint();
    }
    defer job_queue_mutex.unlock();

    if (job_queue_head) |head| {
        job_queue_head = head.next;
        if (job_queue_head == null) {
            job_queue_tail = null;
        }
        return head;
    }
    return null;
}

pub fn startQueueWorker(allocator: std.mem.Allocator, io: std.Io, config: *const config_mod.Config) !void {
    if (worker_threads != null) return;
    worker_should_exit = false;
    global_io = io;
    global_config = config;

    // Initialize registry and sse allocator
    initRegistry(allocator);
    sse.initSse(allocator);

    const worker_count = 2; // concurrent worker threads
    var threads = try allocator.alloc(std.Thread, worker_count);
    for (0..worker_count) |i| {
        threads[i] = try std.Thread.spawn(.{}, queueWorkerLoop, .{});
    }
    worker_threads = threads;
}

fn queueWorkerLoop() void {
    std.debug.print("Background image processing queue worker started.\n", .{});
    const io = global_io.?;
    while (!worker_should_exit) {
        job_queue_sem.waitUncancelable(io);
        if (worker_should_exit) break;

        if (popJob()) |job| {
            media.processJob(job);
        }
    }
}
