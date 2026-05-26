const std = @import("std");
const db = @import("../db.zig");
const server = @import("../server.zig");

pub fn serveStaticFile(allocator: std.mem.Allocator, req: *std.http.Server.Request, io: std.Io, is_authenticated: bool) !bool {
    _ = allocator; // kept for API compatibility; we use a local arena below
    const target = req.head.target;

    if (std.mem.startsWith(u8, target, "/thumbnails/") or std.mem.startsWith(u8, target, "/previews/")) {
        // Use a fresh per-request arena so concurrent requests don't share the same allocator
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();
        if (!is_authenticated) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return true;
        }

        // Decode URL encoding (e.g. %20 -> space)
        const decoded_target = try server.decodeUrl(alloc, target);

        var type_segment: []const u8 = undefined;
        var suffix: []const u8 = undefined;
        if (std.mem.startsWith(u8, decoded_target, "/thumbnails/")) {
            type_segment = "thumbnails";
            suffix = decoded_target[12..];
        } else {
            type_segment = "previews";
            suffix = decoded_target[10..];
        }

        // Suffix is "<uuid>.<ext>". Extract uuid (everything before the dot)
        const dot_idx = std.mem.indexOfScalar(u8, suffix, '.') orelse {
            try req.respond("Bad Request", .{ .status = .bad_request });
            return true;
        };
        const uuid = suffix[0..dot_idx];

        // Retrieve properties from SQLite
        const loc = try db.getPhotoLocation(uuid, alloc);
        if (loc == null) {
            try req.respond("Not Found", .{ .status = .not_found });
            return true;
        }
        // arena owns all allocations; no manual defer-free needed

        // Reconstruct local chronological user path: photos/<username>/<type>/<year>/<month>/<uuid>.<extension>
        const full_path = try std.fmt.allocPrint(alloc, "photos/{s}/{s}/{s}/{s}/{s}.{s}", .{
            loc.?.username,
            type_segment,
            loc.?.year,
            loc.?.month,
            uuid,
            loc.?.extension,
        });

        var file = std.Io.Dir.cwd().openFile(io, full_path, .{}) catch {
            try req.respond("Not Found", .{ .status = .not_found });
            return true;
        };
        defer file.close(io);

        const stat = file.stat(io) catch {
            try req.respond("Internal Error", .{ .status = .internal_server_error });
            return true;
        };

        const file_contents = alloc.alloc(u8, @intCast(stat.size)) catch {
            try req.respond("Internal Error", .{ .status = .internal_server_error });
            return true;
        };
        // arena will free file_contents on scope exit (after req.respond returns)

        var reader = file.reader(io, &.{});
        reader.interface.readSliceAll(file_contents) catch |err| {
            std.debug.print("Failed to read file '{s}': {}\n", .{ full_path, err });
            try req.respond("Error reading file", .{ .status = .internal_server_error });
            return true;
        };

        const is_png = std.mem.eql(u8, loc.?.extension, "png");
        try req.respond(file_contents, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = if (is_png) @as([]const u8, "image/png") else @as([]const u8, "image/jpeg") },
            },
        });
        return true;
    }

    if (std.mem.startsWith(u8, target, "/fonts/")) {
        const font_name = target[7..];
        if (std.mem.eql(u8, font_name, "Roboto-Regular.ttf")) {
            try req.respond(@embedFile("../fonts/Roboto-Regular.ttf"), .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "font/ttf" },
                },
            });
            return true;
        } else if (std.mem.eql(u8, font_name, "Roboto-Medium.ttf")) {
            try req.respond(@embedFile("../fonts/Roboto-Medium.ttf"), .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "font/ttf" },
                },
            });
            return true;
        } else if (std.mem.eql(u8, font_name, "Roboto-Bold.ttf")) {
            try req.respond(@embedFile("../fonts/Roboto-Bold.ttf"), .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "font/ttf" },
                },
            });
            return true;
        }
    }

    return false;
}

pub fn generateGalleryHtml(_: std.mem.Allocator, username: []const u8) ![]u8 {
    // Use a fresh per-request arena for all intermediate allocations so concurrent
    // page loads don't race on the shared auth_ctx.allocator.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var html = std.ArrayList(u8).empty;
    // html is backed by the arena; no errdefer needed — arena.deinit() cleans it up.

    const template = @embedFile("../index_gen.html");
    const placeholder = "<!-- GALLERY_CONTENT -->";
    const split_index = std.mem.indexOf(u8, template, placeholder) orelse {
        std.debug.print("Could not find GALLERY_CONTENT in template\n", .{});
        return error.InvalidTemplate;
    };

    const header = template[0..split_index];
    const footer = template[split_index + placeholder.len ..];

    try html.appendSlice(alloc, header);

    const logout_html = 
        \\<div style="position: absolute; top: 2.5rem; right: 2.5rem; z-index: 10;">
        \\  <form method="POST" action="/logout">
        \\      <button type="submit" style="padding: 0.75rem 1.5rem; background: var(--md-sys-color-error-container); color: var(--md-sys-color-on-error-container); border: none; border-radius: var(--md-sys-shape-corner-full); cursor: pointer; font-weight: 700; font-family: inherit; font-size: 1rem; transition: transform 0.2s cubic-bezier(0.2, 0, 0, 1);" onmouseover="this.style.transform='scale(1.05)'" onmouseout="this.style.transform='scale(1)'">Logout</button>
        \\  </form>
        \\</div>
    ;
    try html.appendSlice(alloc, logout_html);

    // Retrieve user photos from SQLite chronologically.
    // getUserPhotos allocates into alloc (the arena); the arena frees all of it on exit.
    const photos = try db.getUserPhotos(username, alloc);

    // Render photos as flat siblings in a single flexbox container.
    // The browser dynamically wraps and justifies them with zero CLS using flex-grow & aspect-ratio.
    for (photos) |r| {
        const fw: f64 = if (r.width) |w| @floatFromInt(w) else 600.0;
        const fh: f64 = if (r.height) |h| @floatFromInt(h) else 400.0;
        // Clamp degenerate ratios (e.g. 0-dimension photos)
        const raw_ratio = fw / fh;
        const ratio = if (raw_ratio > 0.1 and raw_ratio < 10.0) raw_ratio else 1.5;

        // Using flat list flexbox with ratio-based flex-basis for automatic responsive row packing
        const card = try std.fmt.allocPrint(alloc,
            \\        <div class="card" style="flex:{d:.4} 1 calc({d:.4} * var(--target-h)); aspect-ratio:{d:.4};" onclick="openLightbox('/previews/{s}.{s}')">
            \\            <img src="/thumbnails/{s}.{s}" alt="{s}" loading="lazy">
            \\            <p>{s}</p>
            \\        </div>
            \\
        , .{ ratio, ratio, ratio, r.uuid, r.extension, r.uuid, r.extension, r.filename, r.filename });
        try html.appendSlice(alloc, card);
    }

    // Append the dynamic spacer to prevent the last row from stretching
    try html.appendSlice(alloc, "        <div class=\"gallery-spacer\"></div>\n");

    try html.appendSlice(alloc, footer);

    // Copy the finished HTML into page_allocator memory — caller (server.zig) frees
    // it with `defer std.heap.page_allocator.free(html)`.
    const result = try std.heap.page_allocator.dupe(u8, html.items);
    return result;
}
