const std = @import("std");
const db = @import("../../db.zig");
const server = @import("../../server.zig");
const processor = @import("../../processor.zig");
const config_mod = @import("../../config.zig");
const components = @import("components.zig");

extern "c" fn time(t: ?*i64) i64;

pub fn generateGalleryHtml(_: std.mem.Allocator, username: []const u8, thumbnail_height: i32) ![]u8 {
    // Use a fresh per-request arena for all intermediate allocations so concurrent
    // page loads don't race on the shared auth_ctx.allocator.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var html = std.ArrayList(u8).empty;
    // html is backed by the arena; no errdefer needed — arena.deinit() cleans it up.

    const template = @embedFile("../../index.html");
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

    // Collect unique years for dynamic filtering dropdown
    var years_list = std.ArrayList([]const u8).empty;
    defer years_list.deinit(alloc);

    for (photos) |p| {
        const ym = components.getDisplayYearMonth(p);
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

    // Build filter dropdown HTML
    var filter_html = std.ArrayList(u8).empty;
    
    // Year Select
    try filter_html.appendSlice(alloc, "<div class=\"filter-select-container\"><select id=\"filter-year\" class=\"md-filter-select\" onchange=\"filterGallery()\" aria-label=\"Filter by Year\"><option value=\"all\">All Years</option>");
    for (years_list.items) |y| {
        const option = try std.fmt.allocPrint(alloc, "<option value=\"{s}\">{s}</option>", .{ y, y });
        try filter_html.appendSlice(alloc, option);
    }
    try filter_html.appendSlice(alloc, "</select></div>\n");

    const hardcoded_admin = 
        \\      <a href="/users" class="md-header-logout-icon-btn" title="User Management" aria-label="User Management">
        \\          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor">
        \\              <path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.06-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.05-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.56-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22l-1.92 3.32c-.12.22-.07.49-.12.61l2.03 1.58c-.04.3-.06.61-.06.94s.02.64.06.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .43-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.49-.12-.61l-2.03-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/>
        \\          </svg>
        \\      </a>
    ;
    var logout_html: []const u8 = @embedFile("../../templates/components/logout.html");
    logout_html = try components.replacePlaceholder(alloc, logout_html, "<!-- ADMIN_BTN -->", hardcoded_admin);
    logout_html = try components.replacePlaceholder(alloc, logout_html, "<!-- AVATAR_HTML -->", "");

    const selection_actions_html = @embedFile("../../templates/components/selection_actions.html");

    try html.appendSlice(alloc, filter_html.items);
    try html.appendSlice(alloc, logout_html);
    try html.appendSlice(alloc, selection_actions_html);

    try html.appendSlice(alloc, part3);

    // Render photos as flat siblings in a single flexbox container.
    // The browser dynamically wraps and justifies them with zero CLS using flex-grow & aspect-ratio.
    for (photos, 0..) |r, idx| {
        const card = try components.renderMediaCard(alloc, r, idx);
        try html.appendSlice(alloc, card);
    }

    // Append the dynamic spacer to prevent the last row from stretching
    try html.appendSlice(alloc, "        <div class=\"gallery-spacer\"></div>\n");

    try html.appendSlice(alloc, part4);

    var final_html: []const u8 = html.items;
    final_html = try components.replacePlaceholder(alloc, final_html, "<!-- SHARED_MODALS -->", components.shared_modals_html);

    // Copy the finished HTML into page_allocator memory — caller (server.zig) frees
    // it with `defer std.heap.page_allocator.free(html)`.
    const result = try std.heap.page_allocator.dupe(u8, final_html);
    return result;
}

fn getMonthName(month: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, month, " ");
    if (std.mem.eql(u8, trimmed, "01") or std.mem.eql(u8, trimmed, "1")) return "January";
    if (std.mem.eql(u8, trimmed, "02") or std.mem.eql(u8, trimmed, "2")) return "February";
    if (std.mem.eql(u8, trimmed, "03") or std.mem.eql(u8, trimmed, "3")) return "March";
    if (std.mem.eql(u8, trimmed, "04") or std.mem.eql(u8, trimmed, "4")) return "April";
    if (std.mem.eql(u8, trimmed, "05") or std.mem.eql(u8, trimmed, "5")) return "May";
    if (std.mem.eql(u8, trimmed, "06") or std.mem.eql(u8, trimmed, "6")) return "June";
    if (std.mem.eql(u8, trimmed, "07") or std.mem.eql(u8, trimmed, "7")) return "July";
    if (std.mem.eql(u8, trimmed, "08") or std.mem.eql(u8, trimmed, "8")) return "August";
    if (std.mem.eql(u8, trimmed, "09") or std.mem.eql(u8, trimmed, "9")) return "September";
    if (std.mem.eql(u8, trimmed, "10")) return "October";
    if (std.mem.eql(u8, trimmed, "11")) return "November";
    if (std.mem.eql(u8, trimmed, "12")) return "December";
    return month;
}

pub fn generateAlbumsHtml(allocator: std.mem.Allocator, username: []const u8) ![]u8 {
    _ = allocator;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var html = std.ArrayList(u8).empty;

    const template = @embedFile("../../albums.html");
    const lcp_placeholder = "<!-- LCP_PRELOAD -->";
    const logout_placeholder = "<!-- GALLERY_LOGOUT -->";
    const content_placeholder = "<!-- ALBUMS_CONTENT -->";

    const lcp_idx = std.mem.indexOf(u8, template, lcp_placeholder) orelse {
        std.debug.print("Could not find LCP_PRELOAD in template\n", .{});
        return error.InvalidTemplate;
    };
    const logout_idx = std.mem.indexOf(u8, template, logout_placeholder) orelse {
        std.debug.print("Could not find GALLERY_LOGOUT in template\n", .{});
        return error.InvalidTemplate;
    };
    const content_idx = std.mem.indexOf(u8, template, content_placeholder) orelse {
        std.debug.print("Could not find ALBUMS_CONTENT in template\n", .{});
        return error.InvalidTemplate;
    };

    const part1 = template[0..lcp_idx];
    const part2 = template[lcp_idx + lcp_placeholder.len .. logout_idx];
    const part3 = template[logout_idx + logout_placeholder.len .. content_idx];
    const part4 = template[content_idx + content_placeholder.len ..];

    // Retrieve user albums
    const albums = try db.getAlbums(username, alloc);

    try html.appendSlice(alloc, part1);

    if (albums.len > 0) {
        const first_album = albums[0];
        if (first_album.cover_photo_uuid) |cover_uuid| {
            const ext = first_album.cover_photo_extension orelse "jpg";
            const preload_tag = try std.fmt.allocPrint(alloc,
                "<link rel=\"preload\" as=\"image\" href=\"/thumbnails/{s}.{s}\" fetchpriority=\"high\">",
                .{ cover_uuid, ext }
            );
            try html.appendSlice(alloc, preload_tag);
        }
    }

    const user_opt = try db.getUser(username, alloc);
    const is_admin = if (user_opt) |u| u.is_admin else false;
    const avatar_ext = if (user_opt) |u| u.avatar_ext else null;

    var avatar_html: []const u8 = "";
    if (avatar_ext) |ext| {
        var avatar_raw: []const u8 = @embedFile("../../templates/components/avatar_img.html");
        avatar_raw = try components.replacePlaceholder(alloc, avatar_raw, "<!-- USERNAME -->", username);
        avatar_html = try components.replacePlaceholder(alloc, avatar_raw, "<!-- EXT -->", ext);
    } else {
        avatar_html = @embedFile("../../templates/components/avatar_default.html");
    }

    const admin_btn = if (is_admin) @embedFile("../../templates/components/admin_btn.html") else "";

    var logout_html: []const u8 = @embedFile("../../templates/components/logout.html");
    logout_html = try components.replacePlaceholder(alloc, logout_html, "<!-- ADMIN_BTN -->", admin_btn);
    logout_html = try components.replacePlaceholder(alloc, logout_html, "<!-- AVATAR_HTML -->", avatar_html);

    try html.appendSlice(alloc, logout_html);
    try html.appendSlice(alloc, part2);
    try html.appendSlice(alloc, part3);

    if (albums.len == 0) {
        try html.appendSlice(alloc, @embedFile("../../templates/components/album_empty.html"));
    } else {
        for (albums, 0..) |a, idx| {
            var cover_html: []const u8 = undefined;
            const loading_attr = if (idx < 4) "" else " loading=\"lazy\"";
            const priority_attr = if (idx == 0) " fetchpriority=\"high\"" else "";
            
            const safe_name = try server.htmlEscape(alloc, a.name);
            defer alloc.free(safe_name);
            
            if (a.cover_photo_uuid) |cover_uuid| {
                const ext = a.cover_photo_extension orelse "jpg";
                var cover_raw: []const u8 = @embedFile("../../templates/components/album_cover_img.html");
                cover_raw = try components.replacePlaceholder(alloc, cover_raw, "<!-- COVER_UUID -->", cover_uuid);
                cover_raw = try components.replacePlaceholder(alloc, cover_raw, "<!-- EXT -->", ext);
                cover_raw = try components.replacePlaceholder(alloc, cover_raw, "<!-- LOADING_ATTR -->", loading_attr);
                cover_raw = try components.replacePlaceholder(alloc, cover_raw, "<!-- PRIORITY_ATTR -->", priority_attr);
                cover_html = try components.replacePlaceholder(alloc, cover_raw, "<!-- SAFE_NAME -->", safe_name);
            } else {
                cover_html = @embedFile("../../templates/components/album_cover_default.html");
            }

            const desc = a.description orelse "";
            const safe_desc = try server.htmlEscape(alloc, desc);
            defer alloc.free(safe_desc);
            const photo_count_text = if (a.photo_count == 1) "1 photo" else try std.fmt.allocPrint(alloc, "{d} photos", .{a.photo_count});

            var card_html: []const u8 = @embedFile("../../templates/components/album_card.html");
            card_html = try components.replacePlaceholder(alloc, card_html, "<!-- UUID -->", a.uuid);
            card_html = try components.replacePlaceholder(alloc, card_html, "<!-- COVER_HTML -->", cover_html);
            card_html = try components.replacePlaceholder(alloc, card_html, "<!-- SAFE_NAME -->", safe_name);
            card_html = try components.replacePlaceholder(alloc, card_html, "<!-- PHOTO_COUNT_TEXT -->", photo_count_text);
            card_html = try components.replacePlaceholder(alloc, card_html, "<!-- SAFE_DESC -->", safe_desc);
            
            try html.appendSlice(alloc, card_html);
        }
    }

    try html.appendSlice(alloc, part4);

    const result = try std.heap.page_allocator.dupe(u8, html.items);
    return result;
}
pub fn generateAlbumDetailHtml(allocator: std.mem.Allocator, username: []const u8, album_uuid: []const u8, thumbnail_height: i32) !?[]u8 {
    _ = allocator;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const album_record = try db.getAlbum(username, album_uuid, alloc);
    const album = album_record orelse return null;

    const template = @embedFile("../../album_detail.html");

    // 1. Dynamic style tag
    const dynamic_style = try std.fmt.allocPrint(alloc,
        "<style>:root {{ --target-h: {d}px; }}</style>\n",
        .{thumbnail_height}
    );

    // 2. LCP Preload tag
    const photos = try db.getAlbumPhotos(username, album_uuid, alloc);
    const lcp_tag = if (photos.len > 0) blk: {
        const first_photo = photos[0];
        break :blk try std.fmt.allocPrint(alloc,
            "<link rel=\"preload\" as=\"image\" href=\"/thumbnails/{s}.{s}\" fetchpriority=\"high\">",
            .{ first_photo.uuid, first_photo.extension }
        );
    } else "";

    // 3. Selection actions & Logout HTML
    // Retrieve current user details for the top bar
    const user_opt = try db.getUser(username, alloc);
    const is_admin = if (user_opt) |u| u.is_admin else false;
    const avatar_ext = if (user_opt) |u| u.avatar_ext else null;

    var avatar_html: []const u8 = "";
    if (avatar_ext) |ext| {
        var avatar_raw: []const u8 = @embedFile("../../templates/components/avatar_img.html");
        avatar_raw = try components.replacePlaceholder(alloc, avatar_raw, "<!-- USERNAME -->", username);
        avatar_html = try components.replacePlaceholder(alloc, avatar_raw, "<!-- EXT -->", ext);
    } else {
        avatar_html = @embedFile("../../templates/components/avatar_default.html");
    }

    const admin_btn = if (is_admin) @embedFile("../../templates/components/admin_btn.html") else "";

    var logout_html: []const u8 = @embedFile("../../templates/components/logout.html");
    logout_html = try components.replacePlaceholder(alloc, logout_html, "<!-- ADMIN_BTN -->", admin_btn);
    logout_html = try components.replacePlaceholder(alloc, logout_html, "<!-- AVATAR_HTML -->", avatar_html);

    const selection_actions_html = @embedFile("../../templates/components/selection_actions.html");

    const actions_combined = try std.fmt.allocPrint(alloc, "{s}{s}", .{ logout_html, selection_actions_html });

    // 4. Photo Grid HTML
    var photos_html = std.ArrayList(u8).empty;
    for (photos, 0..) |r, idx| {
        const card = try components.renderMediaCard(alloc, r, idx);
        try photos_html.appendSlice(alloc, card);
    }

    if (photos.len == 0) {
        try photos_html.appendSlice(alloc, @embedFile("../../templates/components/album_photos_empty.html"));
    } else {
        try photos_html.appendSlice(alloc, "        <div class=\"gallery-spacer\"></div>\n");
    }

    // Replace all placeholders
    var result_html: []const u8 = template;
    
    const safe_album_name = try server.htmlEscape(alloc, album.name);
    defer alloc.free(safe_album_name);
    const safe_album_desc = try server.htmlEscape(alloc, album.description orelse "");
    defer alloc.free(safe_album_desc);
    
    // Replace <!-- ALBUM_NAME -->
    result_html = try components.replacePlaceholder(alloc, result_html, "<!-- ALBUM_NAME -->", safe_album_name);
    // Replace <!-- ALBUM_NAME_HEADER -->
    result_html = try components.replacePlaceholder(alloc, result_html, "<!-- ALBUM_NAME_HEADER -->", safe_album_name);
    // Replace <!-- ALBUM_DESC_HEADER -->
    result_html = try components.replacePlaceholder(alloc, result_html, "<!-- ALBUM_DESC_HEADER -->", safe_album_desc);
    // Replace <!-- GALLERY_LOGOUT -->
    result_html = try components.replacePlaceholder(alloc, result_html, "<!-- GALLERY_LOGOUT -->", actions_combined);
    // Replace <!-- ALBUM_PHOTOS_CONTENT -->
    result_html = try components.replacePlaceholder(alloc, result_html, "<!-- ALBUM_PHOTOS_CONTENT -->", photos_html.items);
    // Replace <!-- SHARED_MODALS -->
    result_html = try components.replacePlaceholder(alloc, result_html, "<!-- SHARED_MODALS -->", components.shared_modals_html);
    
    // Inject dynamic style tag (prepend to LCP_PRELOAD or replace LCP_PRELOAD)
    const combined_preload_style = try std.fmt.allocPrint(alloc, "{s}{s}", .{ dynamic_style, lcp_tag });
    result_html = try components.replacePlaceholder(alloc, result_html, "<!-- LCP_PRELOAD -->", combined_preload_style);

    const duplicated = try std.heap.page_allocator.dupe(u8, result_html);
    return duplicated;
}
