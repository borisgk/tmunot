const std = @import("std");
const db = @import("../db.zig");
const server = @import("../server.zig");

pub fn serveStaticFile(allocator: std.mem.Allocator, req: *std.http.Server.Request, io: std.Io, is_authenticated: bool) !bool {
    const target = req.head.target;

    if (std.mem.startsWith(u8, target, "/thumbnails/") or std.mem.startsWith(u8, target, "/previews/")) {
        if (!is_authenticated) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return true;
        }

        // Decode URL encoding (e.g. %20 -> space)
        const decoded_target = try server.decodeUrl(allocator, target);
        defer allocator.free(decoded_target);

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
        const loc = try db.getPhotoLocation(uuid, allocator);
        if (loc == null) {
            try req.respond("Not Found", .{ .status = .not_found });
            return true;
        }
        defer {
            allocator.free(loc.?.username);
            allocator.free(loc.?.year);
            allocator.free(loc.?.month);
            allocator.free(loc.?.extension);
        }

        // Reconstruct local chronological user path: photos/<username>/<type>/<year>/<month>/<uuid>.<extension>
        const full_path = try std.fmt.allocPrint(allocator, "photos/{s}/{s}/{s}/{s}/{s}.{s}", .{
            loc.?.username,
            type_segment,
            loc.?.year,
            loc.?.month,
            uuid,
            loc.?.extension,
        });
        defer allocator.free(full_path);

        var file = std.Io.Dir.cwd().openFile(io, full_path, .{}) catch {
            try req.respond("Not Found", .{ .status = .not_found });
            return true;
        };
        defer file.close(io);

        const stat = file.stat(io) catch {
            try req.respond("Internal Error", .{ .status = .internal_server_error });
            return true;
        };

        const file_contents = allocator.alloc(u8, @intCast(stat.size)) catch {
            try req.respond("Internal Error", .{ .status = .internal_server_error });
            return true;
        };
        defer allocator.free(file_contents);

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

pub fn generateGalleryHtml(allocator: std.mem.Allocator, username: []const u8) ![]u8 {
    var html = std.ArrayList(u8).empty;
    errdefer html.deinit(allocator);

    const template = @embedFile("../index_gen.html");
    const placeholder = "<!-- GALLERY_CONTENT -->";
    const split_index = std.mem.indexOf(u8, template, placeholder) orelse {
        std.debug.print("Could not find GALLERY_CONTENT in template\n", .{});
        return error.InvalidTemplate;
    };

    const header = template[0..split_index];
    const footer = template[split_index + placeholder.len ..];

    try html.appendSlice(allocator, header);

    const logout_html = 
        \\<div style="position: absolute; top: 2.5rem; right: 2.5rem; z-index: 10;">
        \\  <form method="POST" action="/logout">
        \\      <button type="submit" style="padding: 0.75rem 1.5rem; background: var(--md-sys-color-error-container); color: var(--md-sys-color-on-error-container); border: none; border-radius: var(--md-sys-shape-corner-full); cursor: pointer; font-weight: 700; font-family: inherit; font-size: 1rem; transition: transform 0.2s cubic-bezier(0.2, 0, 0, 1);" onmouseover="this.style.transform='scale(1.05)'" onmouseout="this.style.transform='scale(1)'">Logout</button>
        \\  </form>
        \\</div>
    ;
    try html.appendSlice(allocator, logout_html);

    // Retrieve user photos from SQLite chronologically
    const photos = try db.getUserPhotos(username, allocator);
    defer {
        for (photos) |r| {
            allocator.free(r.uuid);
            allocator.free(r.username);
            allocator.free(r.filename);
            allocator.free(r.extension);
            allocator.free(r.year);
            allocator.free(r.month);
            allocator.free(r.day);
            if (r.shooting_date) |sd| allocator.free(sd);
            allocator.free(r.upload_date);
        }
        allocator.free(photos);
    }

    for (photos) |r| {
        // Output gallery card displaying the original human-readable filename, but routes securely via UUID endpoints
        const card = try std.fmt.allocPrint(allocator,
            \\        <div class="card" onclick="openLightbox('/previews/{s}.{s}')">
            \\            <img src="/thumbnails/{s}.{s}" alt="{s}" loading="lazy">
            \\            <p>{s}</p>
            \\        </div>
        , .{ r.uuid, r.extension, r.uuid, r.extension, r.filename, r.filename });
        defer allocator.free(card);
        try html.appendSlice(allocator, card);
    }

    try html.appendSlice(allocator, footer);

    return html.toOwnedSlice(allocator);
}
