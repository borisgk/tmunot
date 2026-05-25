const std = @import("std");

pub fn serveStaticFile(req: *std.http.Server.Request, io: std.Io, is_authenticated: bool) !bool {
    const target = req.head.target;
    
    if (std.mem.startsWith(u8, target, "/thumbnails/") or std.mem.startsWith(u8, target, "/previews/")) {
        if (!is_authenticated) {
            try req.respond("Unauthorized", .{ .status = .unauthorized });
            return true;
        }

        var path_buf: [1024]u8 = undefined;
        const relative_path = target[1..];
        const full_path = std.fmt.bufPrint(&path_buf, "output/{s}", .{relative_path}) catch {
            try req.respond("Path too long", .{ .status = .bad_request });
            return true;
        };

        var file = std.Io.Dir.cwd().openFile(io, full_path, .{}) catch {
            try req.respond("Not Found", .{ .status = .not_found });
            return true;
        };
        defer file.close(io);

        const stat = file.stat(io) catch {
            try req.respond("Internal Error", .{ .status = .internal_server_error });
            return true;
        };

        const file_contents = std.heap.page_allocator.alloc(u8, @intCast(stat.size)) catch {
            try req.respond("Internal Error", .{ .status = .internal_server_error });
            return true;
        };
        defer std.heap.page_allocator.free(file_contents);

        var reader = file.reader(io, &.{});
        reader.interface.readSliceAll(file_contents) catch |err| {
            std.debug.print("Failed to read file '{s}': {}\n", .{full_path, err});
            try req.respond("Error reading file", .{ .status = .internal_server_error });
            return true;
        };

        try req.respond(file_contents, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = if (std.mem.endsWith(u8, full_path, ".png")) @as([]const u8, "image/png") else @as([]const u8, "image/jpeg") },
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

pub fn generateGalleryHtml(io: std.Io) ![]u8 {
    const allocator = std.heap.page_allocator;
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

    const cwd = std.Io.Dir.cwd();
    var dir = cwd.openDir(io, "output/thumbnails", .{ .iterate = true }) catch return html.toOwnedSlice(allocator);
    defer dir.close(io);
    
    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind == .file) {
            const card = try std.fmt.allocPrint(allocator,
                \\        <div class="card" onclick="openLightbox('/previews/{s}')">
                \\            <img src="/thumbnails/{s}" alt="{s}" loading="lazy">
                \\            <p>{s}</p>
                \\        </div>
            , .{ entry.name, entry.name, entry.name, entry.name });
            try html.appendSlice(allocator, card);
        }
    }

    try html.appendSlice(allocator, footer);

    return html.toOwnedSlice(allocator);
}
