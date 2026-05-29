const std = @import("std");
const db = @import("../db.zig");
const server = @import("../server.zig");
const processor = @import("../processor.zig");

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

        // Shield SQLite from polling: if the job is active in registry, return 404 immediately
        if (try processor.getActiveJob(uuid, alloc)) |_| {
            try req.respond("Not Found", .{ .status = .not_found });
            return true;
        }

        // Retrieve properties from SQLite
        const loc = try db.getPhotoLocation(uuid, alloc);
        if (loc == null) {
            try req.respond("Not Found", .{ .status = .not_found });
            return true;
        }

        // Conditional Request validation for aggressive browser caching (F5/Reload support)
        var if_none_match: ?[]const u8 = null;
        var header_it = req.iterateHeaders();
        while (header_it.next()) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "if-none-match")) {
                if_none_match = std.mem.trim(u8, header.value, " \"");
            }
        }

        const etag_val = try std.fmt.allocPrint(alloc, "\"{s}\"", .{uuid});

        if (if_none_match) |etag| {
            var clean_etag = etag;
            if (std.mem.startsWith(u8, clean_etag, "W/") or std.mem.startsWith(u8, clean_etag, "w/")) {
                clean_etag = clean_etag[2..];
            }
            clean_etag = std.mem.trim(u8, clean_etag, " \"");

            if (std.mem.eql(u8, clean_etag, uuid)) {
                try req.respond("", .{
                    .status = .not_modified,
                    .extra_headers = &.{
                        .{ .name = "Cache-Control", .value = "public, max-age=31536000, immutable" },
                        .{ .name = "ETag", .value = etag_val },
                    },
                });
                return true;
            }
        }

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
                .{ .name = "Content-Type", .value = if (is_png) @as([]const u8, "image/png") else @as([]const u8, "image/jpeg") },
                .{ .name = "Cache-Control", .value = "public, max-age=31536000, immutable" },
                .{ .name = "ETag", .value = etag_val },
            },
        });
        return true;
    }

    if (std.mem.startsWith(u8, target, "/fonts/")) {
        const font_name = target[7..];
        if (std.mem.eql(u8, font_name, "RobotoFlex-VariableFont.woff2")) {
            try req.respond(@embedFile("../fonts/RobotoFlex-VariableFont.woff2"), .{
                .extra_headers = &.{
                    .{ .name = "Content-Type", .value = "font/woff2" },
                    .{ .name = "Cache-Control", .value = "public, max-age=31536000, immutable" },
                },
            });
            return true;
        }
    }

    return false;
}

pub fn generateGalleryHtml(_: std.mem.Allocator, username: []const u8, thumbnail_height: i32) ![]u8 {
    // Use a fresh per-request arena for all intermediate allocations so concurrent
    // page loads don't race on the shared auth_ctx.allocator.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var html = std.ArrayList(u8).empty;
    // html is backed by the arena; no errdefer needed — arena.deinit() cleans it up.

    const template = @embedFile("../index_gen.html");
    const lcp_placeholder = "<!-- LCP_PRELOAD -->";
    const logout_placeholder = "<!-- GALLERY_LOGOUT -->";
    const content_placeholder = "<!-- GALLERY_CONTENT -->";

    const lcp_idx = std.mem.indexOf(u8, template, lcp_placeholder) orelse {
        std.debug.print("Could not find LCP_PRELOAD in template\n", .{});
        return error.InvalidTemplate;
    };
    const logout_idx = std.mem.indexOf(u8, template, logout_placeholder) orelse {
        std.debug.print("Could not find GALLERY_LOGOUT in template\n", .{});
        return error.InvalidTemplate;
    };
    const content_idx = std.mem.indexOf(u8, template, content_placeholder) orelse {
        std.debug.print("Could not find GALLERY_CONTENT in template\n", .{});
        return error.InvalidTemplate;
    };

    const part1 = template[0..lcp_idx];
    const part2 = template[lcp_idx + lcp_placeholder.len .. logout_idx];
    const part3 = template[logout_idx + logout_placeholder.len .. content_idx];
    const part4 = template[content_idx + content_placeholder.len ..];

    // Retrieve user photos from SQLite chronologically.
    // getUserPhotos allocates into alloc (the arena); the arena frees all of it on exit.
    const photos = try db.getUserPhotos(username, alloc);

    try html.appendSlice(alloc, part1);

    // Inject dynamic thumbnail height override in <head>
    const dynamic_style = try std.fmt.allocPrint(alloc,
        "<style>:root {{ --target-h: {d}px; }}</style>\n",
        .{thumbnail_height}
    );
    try html.appendSlice(alloc, dynamic_style);

    // Dynamic LCP Preload in HTML Head: If there are photos, preload the first thumbnail immediately
    if (photos.len > 0) {
        const first_photo = photos[0];
        const preload_tag = try std.fmt.allocPrint(alloc,
            "<link rel=\"preload\" as=\"image\" href=\"/thumbnails/{s}.{s}\" fetchpriority=\"high\">",
            .{ first_photo.uuid, first_photo.extension }
        );
        try html.appendSlice(alloc, preload_tag);
    }
    
    try html.appendSlice(alloc, part2);

    const logout_html = 
        \\  <form method="POST" action="/logout" style="margin: 0;">
        \\      <button type="submit" class="md-header-logout-icon-btn" title="Logout" aria-label="Logout">
        \\          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
        \\              <path d="M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h8v-2H4V5z"/>
        \\          </svg>
        \\      </button>
        \\  </form>
    ;
    try html.appendSlice(alloc, logout_html);

    try html.appendSlice(alloc, part3);

    // Render photos as flat siblings in a single flexbox container.
    // The browser dynamically wraps and justifies them with zero CLS using flex-grow & aspect-ratio.
    for (photos, 0..) |r, idx| {
        const fw: f64 = if (r.width) |w| @floatFromInt(w) else 600.0;
        const fh: f64 = if (r.height) |h| @floatFromInt(h) else 400.0;
        // Clamp degenerate ratios (e.g. 0-dimension photos)
        const raw_ratio = fw / fh;
        const ratio = if (raw_ratio > 0.1 and raw_ratio < 10.0) raw_ratio else 1.5;

        // Optimization: The first 12 images (approx. 2-3 rows) are treated as potentially above the fold.
        // Eagerly loading them prevents them from being lazy-loaded on large/wide viewports.
        // The first image still keeps fetchpriority="high" on its img tag for maximum prioritization.
        const loading_attr = if (idx < 12) "" else " loading=\"lazy\"";
        const priority_attr = if (idx == 0) " fetchpriority=\"high\"" else "";

        // Using flat list flexbox with ratio-based flex-basis for automatic responsive row packing and fixed height for perfect consistency
        const card = try std.fmt.allocPrint(alloc,
            \\        <div class="card" data-uuid="{s}" style="flex:{d:.4} 1 calc({d:.4} * var(--target-h));" onclick="openLightbox('/previews/{s}.{s}')">
            \\            <button class="card-overflow-btn" aria-label="More options" onclick="toggleMenu(event, '{s}', '{s}')">
            \\                <svg viewBox="0 0 24 24"><path d="M12 8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm0 2c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/></svg>
            \\            </button>
            \\            <div class="card-select-checkbox" onclick="toggleSelect(event)">
            \\                <svg viewBox="0 0 24 24"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z"/></svg>
            \\            </div>
            \\            <img src="/thumbnails/{s}.{s}" alt="{s}"{s}{s}>
            \\            <p>{s}</p>
            \\        </div>
            \\
        , .{ r.uuid, ratio, ratio, r.uuid, r.extension, r.uuid, r.extension, r.uuid, r.extension, r.filename, loading_attr, priority_attr, r.filename });
        try html.appendSlice(alloc, card);
    }

    // Append the dynamic spacer to prevent the last row from stretching
    try html.appendSlice(alloc, "        <div class=\"gallery-spacer\"></div>\n");

    try html.appendSlice(alloc, part4);

    // Copy the finished HTML into page_allocator memory — caller (server.zig) frees
    // it with `defer std.heap.page_allocator.free(html)`.
    const result = try std.heap.page_allocator.dupe(u8, html.items);
    return result;
}
