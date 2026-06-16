const std = @import("std");
const db = @import("../../db.zig");
const templates = @import("templates.zig");

pub fn generateGalleryHtml(allocator: std.mem.Allocator, username: []const u8, thumbnail_height: i32) ![]u8 {
    _ = allocator;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var aw = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    errdefer aw.deinit();
    const writer = &aw.writer;

    // Retrieve user photos from SQLite chronologically.
    const photos = try db.getUserPhotos(username, alloc);

    try writer.writeAll(templates.gallery_head_start);

    // 1. Dynamic style tag
    try templates.renderDynamicStyle(writer, thumbnail_height);

    // 2. Dynamic LCP Preload in HTML Head: If there are photos, preload the first thumbnail immediately
    if (photos.len > 0) {
        const first_photo = photos[0];
        try templates.renderPreloadTag(writer, first_photo.uuid, first_photo.extension);
    }

    try writer.writeAll(templates.gallery_body_top);

    // Get user to see if admin & avatar
    const user_opt = try db.getUser(username, alloc);
    const is_admin = if (user_opt) |u| u.is_admin else false;
    const avatar_ext = if (user_opt) |u| u.avatar_ext else null;

    // Render logout/topbar actions
    try templates.renderLogout(writer, is_admin, username, avatar_ext);

    // Render selection actions
    try templates.renderSelectionActions(writer);

    try writer.writeAll(templates.gallery_header_end);

    // Collect unique years for dynamic filtering dropdown
    var years_list = std.ArrayList([]const u8).empty;
    for (photos) |p| {
        const ym = templates.getDisplayYearMonth(p);
        var year_exists = false;
        for (years_list.items) |y| {
            if (std.mem.eql(u8, y, ym.year)) {
                year_exists = true;
                break;
            }
        }
        if (!year_exists) {
            try years_list.append(alloc, try alloc.dupe(u8, ym.year));
        }
    }

    std.mem.sort([]const u8, years_list.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .gt;
        }
    }.lessThan);

    try templates.renderFilterSelect(writer, years_list.items);

    try writer.writeAll(templates.gallery_main_start);

    // Render photos
    for (photos, 0..) |r, idx| {
        try templates.renderMediaCard(writer, r, idx);
    }

    // Dynamic spacer to prevent the last row from stretching
    try templates.renderGallerySpacer(writer);

    try writer.writeAll(templates.gallery_lightbox);

    // Render shared modals
    try templates.renderSharedModals(writer);

    try writer.writeAll(templates.gallery_footer);

    return try aw.toOwnedSlice();
}

pub fn generateAlbumsHtml(allocator: std.mem.Allocator, username: []const u8) ![]u8 {
    _ = allocator;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var aw = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    errdefer aw.deinit();
    const writer = &aw.writer;

    // Retrieve user albums
    const albums = try db.getAlbums(username, alloc);

    try writer.writeAll(templates.albums_head_start);

    if (albums.len > 0) {
        const first_album = albums[0];
        if (first_album.cover_photo_uuid) |cover_uuid| {
            const ext = first_album.cover_photo_extension orelse "jpg";
            try writer.print(
                \\    <link rel="preload" as="image" href="/thumbnails/{s}.{s}" fetchpriority="high">
                \\
            , .{ cover_uuid, ext });
        }
    }

    try writer.writeAll(templates.albums_body_top);

    const user_opt = try db.getUser(username, alloc);
    const is_admin = if (user_opt) |u| u.is_admin else false;
    const avatar_ext = if (user_opt) |u| u.avatar_ext else null;

    try templates.renderLogout(writer, is_admin, username, avatar_ext);

    try writer.writeAll(templates.albums_main_start);

    if (albums.len == 0) {
        try templates.renderAlbumEmpty(writer);
    } else {
        for (albums, 0..) |a, idx| {
            try templates.renderAlbumCard(writer, a.uuid, a.name, a.photo_count, a.description, a.cover_photo_uuid, a.cover_photo_extension, idx);
        }
    }

    try writer.writeAll(templates.albums_footer);

    return try aw.toOwnedSlice();
}

pub fn generateAlbumDetailHtml(allocator: std.mem.Allocator, username: []const u8, album_uuid: []const u8, thumbnail_height: i32) !?[]u8 {
    _ = allocator;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const album_record = try db.getAlbum(username, album_uuid, alloc);
    const album = album_record orelse return null;

    var aw = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    errdefer aw.deinit();
    const writer = &aw.writer;

    const photos = try db.getAlbumPhotos(username, album_uuid, alloc);

    try writer.writeAll(templates.album_detail_head_start);

    try templates.writeEscapedHtml(writer, album.name);

    try writer.writeAll(templates.album_detail_head_end);

    // 1. Dynamic style tag
    try templates.renderDynamicStyle(writer, thumbnail_height);

    // 2. LCP Preload tag
    if (photos.len > 0) {
        const first_photo = photos[0];
        try templates.renderPreloadTag(writer, first_photo.uuid, first_photo.extension);
    }

    try writer.writeAll(templates.album_detail_body_top);

    try templates.writeEscapedHtml(writer, album.name);

    try writer.writeAll(templates.album_detail_body_title_end);

    const user_opt = try db.getUser(username, alloc);
    const is_admin = if (user_opt) |u| u.is_admin else false;
    const avatar_ext = if (user_opt) |u| u.avatar_ext else null;

    try templates.renderLogout(writer, is_admin, username, avatar_ext);
    try templates.renderSelectionActions(writer);

    try writer.writeAll(templates.album_detail_main_start);

    try templates.writeEscapedHtml(writer, album.name);

    try writer.writeAll(templates.album_detail_desc_start);

    if (album.description) |desc| {
        try templates.writeEscapedHtml(writer, desc);
    }

    try writer.writeAll(templates.album_detail_desc_end);

    if (photos.len == 0) {
        try templates.renderAlbumPhotosEmpty(writer);
    } else {
        for (photos, 0..) |r, idx| {
            try templates.renderMediaCard(writer, r, idx);
        }
        try templates.renderGallerySpacer(writer);
    }

    try writer.writeAll(templates.gallery_lightbox);
    try templates.renderSharedModals(writer);
    try writer.writeAll(templates.album_detail_footer);

    return try aw.toOwnedSlice();
}

pub fn generateLoginHtml(allocator: std.mem.Allocator, csrf_token: []const u8, error_message: []const u8) ![]u8 {
    _ = allocator;
    var aw = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    errdefer aw.deinit();
    const writer = &aw.writer;

    try templates.renderLoginHtml(writer, csrf_token, error_message);

    return try aw.toOwnedSlice();
}

pub fn generateUploadHtml(allocator: std.mem.Allocator) ![]u8 {
    _ = allocator;
    var aw = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    errdefer aw.deinit();
    const writer = &aw.writer;

    try templates.renderUploadHtml(writer);

    return try aw.toOwnedSlice();
}

pub fn generateUsersHtml(allocator: std.mem.Allocator) ![]u8 {
    _ = allocator;
    var aw = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    errdefer aw.deinit();
    const writer = &aw.writer;

    try templates.renderUsersHtml(writer);

    return try aw.toOwnedSlice();
}
