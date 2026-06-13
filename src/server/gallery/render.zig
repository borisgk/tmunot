const std = @import("std");
const db = @import("../../db.zig");
const server = @import("../../server.zig");
const processor = @import("../../processor.zig");
const config_mod = @import("../../config.zig");

extern "c" fn time(t: ?*i64) i64;

const shared_modals_html = 
    \\    <!-- Global Overflow Menu -->
    \\    <div id="global-menu" class="md-menu">
    \\        <button class="md-menu-item" id="menu-metadata">
    \\            <svg viewBox="0 0 24 24"><path fill="currentColor" d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/></svg>
    \\            <span>View metadata</span>
    \\        </button>
    \\        <button class="md-menu-item" id="menu-download">
    \\            <svg viewBox="0 0 24 24"><path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM17 13l-5 5-5-5h3V9h4v4h3z"/></svg>
    \\            <span>Download</span>
    \\        </button>
    \\        <button class="md-menu-item" id="menu-add-to-album">
    \\            <svg viewBox="0 0 24 24"><path fill="currentColor" d="M20 6h-8l-2-2H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm-1 8h-3v3h-2v-3h-3v-2h3V9h2v3h3v2z"/></svg>
    \\            <span>Add to album</span>
    \\        </button>
    \\        <button class="md-menu-item md-menu-item--danger" id="menu-delete">
    \\            <svg viewBox="0 0 24 24"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>
    \\            <span>Delete</span>
    \\        </button>
    \\    </div>
    \\
    \\    <!-- Metadata Modal -->
    \\    <div id="metadata-modal" class="lightbox" onclick="closeMetadataModal(event)">
    \\        <div class="modal-content" style="background: var(--md-sys-color-surface-container); padding: 24px; border-radius: 28px; width: 500px; max-width: 90%; max-height: 80vh; display: flex; flex-direction: column; box-shadow: 0 4px 12px rgba(0,0,0,0.15);" onclick="event.stopPropagation()">
    \\            <h2 style="margin-top: 0; color: var(--md-sys-color-on-surface); margin-bottom: 16px;">Photo Metadata</h2>
    \\            <div id="metadata-list" style="overflow-y: auto; flex: 1; margin-bottom: 24px; display: flex; flex-direction: column; gap: 8px;">
    \\                <!-- Metadata items loaded dynamically -->
    \\            </div>
    \\            <div style="text-align: right;">
    \\                <button class="md-menu-item" style="display: inline-block; width: auto; background: var(--md-sys-color-primary); color: var(--md-sys-color-on-primary); border: none; padding: 10px 24px; border-radius: 20px; font-weight: 500; cursor: pointer;" onclick="closeMetadataModal({target:{id:'metadata-modal'}})">Close</button>
    \\            </div>
    \\        </div>
    \\    </div>
    \\
    \\    <!-- Album Selection Modal -->
    \\    <div id="album-select-modal" class="lightbox" onclick="closeAlbumSelectModal(event)">
    \\        <div class="modal-content" style="background: var(--md-sys-color-surface-container); padding: 24px; border-radius: 28px; width: 400px; max-width: 90%; box-shadow: 0 4px 12px rgba(0,0,0,0.15);" onclick="event.stopPropagation()">
    \\            <h2 style="margin-top: 0; color: var(--md-sys-color-on-surface); margin-bottom: 16px;">Add to Album</h2>
    \\            <div id="album-list-container" style="max-height: 250px; overflow-y: auto; margin-bottom: 24px; display: flex; flex-direction: column; gap: 8px;">
    \\                <!-- Album items loaded dynamically -->
    \\            </div>
    \\            <div style="text-align: right;">
    \\                <button class="md-menu-item" style="display: inline-block; width: auto; margin-right: 8px; background: transparent; border: none; cursor: pointer; color: var(--md-sys-color-on-surface);" onclick="closeAlbumSelectModal({target:{id:'album-select-modal'}})">Cancel</button>
    \\                <button id="submit-add-to-album" style="background: var(--md-sys-color-primary); color: var(--md-sys-color-on-primary); border: none; padding: 10px 24px; border-radius: 20px; font-weight: 500; cursor: pointer;">Add</button>
    \\            </div>
    \\        </div>
    \\    </div>
    \\
    \\    <!-- Profile Modal -->
    \\    <div id="profile-modal" class="lightbox" onclick="closeProfileModal(event)">
    \\        <div class="modal-content" style="background: var(--md-sys-color-surface-container); padding: 24px; border-radius: 28px; width: 400px; max-width: 90%; box-shadow: 0 4px 12px rgba(0,0,0,0.15);" onclick="event.stopPropagation()">
    \\            <h2 style="margin-top: 0; color: var(--md-sys-color-on-surface); margin-bottom: 16px;">My Profile</h2>
    \\            <form id="profile-form">
    \\                <div style="margin-bottom: 16px;">
    \\                    <label style="display: block; font-weight: 500; margin-bottom: 4px;">Avatar</label>
    \\                    <input type="file" id="profile-avatar-upload" accept="image/png, image/jpeg, image/webp" style="width: 100%; border: 1px solid var(--md-sys-color-outline); border-radius: 8px; padding: 8px; box-sizing: border-box;">
    \\                </div>
    \\                <div style="margin-bottom: 16px;">
    \\                    <label style="display: block; font-weight: 500; margin-bottom: 4px;">Real Name</label>
    \\                    <input type="text" id="profile-real-name" style="width: 100%; border: 1px solid var(--md-sys-color-outline); border-radius: 8px; padding: 12px; box-sizing: border-box; background: transparent; color: inherit;">
    \\                </div>
    \\                <div style="margin-bottom: 24px;">
    \\                    <label style="display: block; font-weight: 500; margin-bottom: 4px;">New Password (leave blank to keep current)</label>
    \\                    <input type="password" id="profile-password" style="width: 100%; border: 1px solid var(--md-sys-color-outline); border-radius: 8px; padding: 12px; box-sizing: border-box; background: transparent; color: inherit;">
    \\                </div>
    \\                <div style="text-align: right;">
    \\                    <button type="button" class="md-menu-item" style="display: inline-block; width: auto; margin-right: 8px; background: transparent; border: none; cursor: pointer; color: var(--md-sys-color-on-surface);" onclick="closeProfileModal({target:{id:'profile-modal'}})">Cancel</button>
    \\                    <button type="submit" style="background: var(--md-sys-color-primary); color: var(--md-sys-color-on-primary); border: none; padding: 10px 24px; border-radius: 20px; font-weight: 500; cursor: pointer;">Save</button>
    \\                </div>
    \\            </form>
    \\        </div>
    \\    </div>
;

pub fn generateGalleryHtml(_: std.mem.Allocator, username: []const u8, thumbnail_height: i32) ![]u8 {
    // Use a fresh per-request arena for all intermediate allocations so concurrent
    // page loads don't race on the shared auth_ctx.allocator.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var html = std.ArrayList(u8).empty;
    // html is backed by the arena; no errdefer needed — arena.deinit() cleans it up.

    const template = @embedFile("../../index_gen.html");
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
        const ym = getDisplayYearMonth(p);
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

    const logout_html = 
        \\  <div style="display: flex; align-items: center; gap: 8px;">
        \\      <a href="/users" class="md-header-logout-icon-btn" title="User Management" aria-label="User Management">
        \\          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor">
        \\              <path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.06-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.05-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.56-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22l-1.92 3.32c-.12.22-.07.49.12.61l2.03 1.58c-.04.3-.06.61-.06.94s.02.64.06.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .43-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.49-.12-.61l-2.03-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/>
        \\          </svg>
        \\      </a>
        \\      <form method="POST" action="/logout" style="margin: 0;">
        \\          <button type="submit" class="md-header-logout-icon-btn" title="Logout" aria-label="Logout">
        \\              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
        \\                  <path d="M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h8v-2H4V5z"/>
        \\              </svg>
        \\          </button>
        \\      </form>
        \\  </div>
    ;

    const selection_actions_html =
        \\  <div id="selection-actions" class="selection-actions-container" style="display: none;">
        \\      <button class="md-selection-icon-btn" onclick="bulkDownload()" title="Download selected" aria-label="Download selected">
        \\          <svg viewBox="0 0 24 24"><path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM17 13l-5 5-5-5h3V9h4v4h3z"/></svg>
        \\      </button>
        \\      <button class="md-selection-icon-btn" id="bulk-add-to-album-btn" onclick="openBulkAddToAlbum()" title="Add to album" aria-label="Add to album">
        \\          <svg viewBox="0 0 24 24"><path fill="currentColor" d="M20 6h-8l-2-2H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm-1 8h-3v3h-2v-3h-3v-2h3V9h2v3h3v2z"/></svg>
        \\      </button>
        \\      <button class="md-selection-icon-btn" onclick="bulkDelete()" title="Delete selected" aria-label="Delete selected" style="color: var(--md-sys-color-error, #ba1a1a);">
        \\          <svg viewBox="0 0 24 24"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>
        \\      </button>
        \\  </div>
    ;

    try html.appendSlice(alloc, filter_html.items);
    try html.appendSlice(alloc, logout_html);
    try html.appendSlice(alloc, selection_actions_html);

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

        const ym = getDisplayYearMonth(r);
        const is_video = std.mem.eql(u8, r.extension, "mp4") or
                         std.mem.eql(u8, r.extension, "mov") or
                         std.mem.eql(u8, r.extension, "m4v") or
                         std.mem.eql(u8, r.extension, "webm") or
                         std.mem.eql(u8, r.extension, "avi");

        // Using flat list flexbox with ratio-based flex-basis for automatic responsive row packing and fixed height for perfect consistency
        const card = if (is_video)
            try std.fmt.allocPrint(alloc,
                \\        <div class="card video-card" data-uuid="{s}" data-year="{s}" data-month="{s}" style="flex:{d:.4} 1 calc({d:.4} * var(--target-h));" onclick="openLightbox('/previews/{s}.{s}')">
                \\            <button class="card-overflow-btn" aria-label="More options" onclick="toggleMenu(event, '{s}', '{s}')">
                \\                <svg viewBox="0 0 24 24"><path d="M12 8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm0 2c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/></svg>
                \\            </button>
                \\            <div class="card-select-checkbox" onclick="toggleSelect(event)">
                \\                <svg viewBox="0 0 24 24"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z"/></svg>
                \\            </div>
                \\            <div class="card-video-play-overlay">
                \\                <svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>
                \\            </div>
                \\            <img src="/thumbnails/{s}.{s}" alt="{s}"{s}{s}>
                \\            <p>{s}</p>
                \\        </div>
                \\
            , .{ r.uuid, ym.year, ym.month, ratio, ratio, r.uuid, r.extension, r.uuid, r.extension, r.uuid, r.extension, r.filename, loading_attr, priority_attr, r.filename })
        else
            try std.fmt.allocPrint(alloc,
                \\        <div class="card" data-uuid="{s}" data-year="{s}" data-month="{s}" style="flex:{d:.4} 1 calc({d:.4} * var(--target-h));" onclick="openLightbox('/previews/{s}.{s}')">
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
            , .{ r.uuid, ym.year, ym.month, ratio, ratio, r.uuid, r.extension, r.uuid, r.extension, r.uuid, r.extension, r.filename, loading_attr, priority_attr, r.filename });
        try html.appendSlice(alloc, card);
    }

    // Append the dynamic spacer to prevent the last row from stretching
    try html.appendSlice(alloc, "        <div class=\"gallery-spacer\"></div>\n");

    try html.appendSlice(alloc, part4);

    var final_html: []const u8 = html.items;
    final_html = try replacePlaceholder(alloc, final_html, "<!-- SHARED_MODALS -->", shared_modals_html);

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

fn getDisplayYearMonth(r: db.PhotoRecord) struct { year: []const u8, month: []const u8 } {
    if (r.shooting_date) |sd| {
        if (sd.len >= 10) {
            return .{
                .year = sd[0..4],
                .month = sd[5..7],
            };
        }
    }
    if (r.upload_date.len >= 10) {
        return .{
            .year = r.upload_date[0..4],
            .month = r.upload_date[5..7],
        };
    }
    return .{
        .year = r.year,
        .month = r.month,
    };
}

pub fn generateAlbumsHtml(allocator: std.mem.Allocator, username: []const u8) ![]u8 {
    _ = allocator;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var html = std.ArrayList(u8).empty;

    const template = @embedFile("../../albums_gen.html");
    const logout_placeholder = "<!-- GALLERY_LOGOUT -->";
    const content_placeholder = "<!-- ALBUMS_CONTENT -->";

    const logout_idx = std.mem.indexOf(u8, template, logout_placeholder) orelse {
        std.debug.print("Could not find GALLERY_LOGOUT in template\n", .{});
        return error.InvalidTemplate;
    };
    const content_idx = std.mem.indexOf(u8, template, content_placeholder) orelse {
        std.debug.print("Could not find ALBUMS_CONTENT in template\n", .{});
        return error.InvalidTemplate;
    };

    const part1 = template[0..logout_idx];
    const part2 = template[logout_idx + logout_placeholder.len .. content_idx];
    const part3 = template[content_idx + content_placeholder.len ..];

    try html.appendSlice(alloc, part1);

    const user_opt = try db.getUser(username, alloc);
    const is_admin = if (user_opt) |u| u.is_admin else false;
    const avatar_ext = if (user_opt) |u| u.avatar_ext else null;

    var avatar_html: []const u8 = "";
    if (avatar_ext) |ext| {
        avatar_html = try std.fmt.allocPrint(alloc,
            "<img src=\"/avatars/{s}.{s}\" class=\"md-header-logout-icon-btn\" style=\"border-radius: 50%; object-fit: cover; cursor: pointer; padding: 0; width: 40px; height: 40px;\" onclick=\"openProfileModal()\" alt=\"Profile\">",
            .{ username, ext }
        );
    } else {
        avatar_html = 
            \\<button class="md-header-logout-icon-btn" style="border-radius: 50%; background: var(--md-sys-color-primary-container); color: var(--md-sys-color-on-primary-container); font-weight: 500;" onclick="openProfileModal()" title="Profile">
            \\    <svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>
            \\</button>
        ;
    }

    const admin_btn = if (is_admin) 
        \\      <a href="/users" class="md-header-logout-icon-btn" title="User Management" aria-label="User Management">
        \\          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor">
        \\              <path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.06-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.05-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.56-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22l-1.92 3.32c-.12.22-.07.49-.12.61l2.03 1.58c-.04.3-.06.61-.06.94s.02.64.06.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .43-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.49-.12-.61l-2.03-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/>
        \\          </svg>
        \\      </a>
    else "";

    const logout_html = try std.fmt.allocPrint(alloc,
        \\  <div style="display: flex; align-items: center; gap: 8px;">
        \\{s}
        \\{s}
        \\      <form method="POST" action="/logout" style="margin: 0;">
        \\          <button type="submit" class="md-header-logout-icon-btn" title="Logout" aria-label="Logout">
        \\              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
        \\                  <path d="M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h8v-2H4V5z"/>
        \\              </svg>
        \\          </button>
        \\      </form>
        \\  </div>
        , .{ admin_btn, avatar_html }
    );

    try html.appendSlice(alloc, logout_html);
    try html.appendSlice(alloc, part2);

    // Retrieve user albums
    const albums = try db.getAlbums(username, alloc);

    if (albums.len == 0) {
        try html.appendSlice(alloc, 
            \\<p style="text-align: center; width: 100%; color: var(--md-sys-color-on-surface-variant); padding: 48px 0;">No albums yet.</p>
        );
    } else {
        for (albums) |a| {
            var cover_html: []const u8 = undefined;
            
            if (a.cover_photo_uuid) |cover_uuid| {
                const ext = a.cover_photo_extension orelse "jpg";
                cover_html = try std.fmt.allocPrint(alloc,
                    \\<img src="/thumbnails/{s}.{s}" alt="{s}" style="width: 100%; height: 160px; object-fit: cover; border-radius: 12px 12px 0 0;">
                    , .{ cover_uuid, ext, a.name }
                );
            } else {
                cover_html = 
                    \\<div style="width: 100%; height: 160px; background: var(--md-sys-color-surface-container-high); display: flex; align-items: center; justify-content: center; border-radius: 12px 12px 0 0; color: var(--md-sys-color-primary);">
                    \\    <svg viewBox="0 0 24 24" fill="currentColor" width="48" height="48">
                    \\        <path d="M22 16V4c0-1.1-.9-2-2-2H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2zm-11-4 2.03 2.71L16 11l4 5H8l3-4zM2 6v14c0 1.1.9 2 2 2h14v-2H4V6H2z"/>
                    \\    </svg>
                    \\</div>
                ;
            }

            const desc = a.description orelse "";
            const photo_count_text = if (a.photo_count == 1) "1 photo" else try std.fmt.allocPrint(alloc, "{d} photos", .{a.photo_count});

            const card_html = try std.fmt.allocPrint(alloc,
                \\<div class="album-card" onclick="window.location.href='/albums/{s}'" style="width: 220px; background: var(--md-sys-color-surface-container); border-radius: 16px; box-shadow: 0 2px 6px rgba(0,0,0,0.1); cursor: pointer; transition: transform 0.2s, box-shadow 0.2s; overflow: hidden; display: flex; flex-direction: column;">
                \\    {s}
                \\    <div style="padding: 16px; display: flex; flex-direction: column; gap: 4px;">
                \\        <h3 style="margin: 0; font-size: 1.1rem; font-weight: 600; color: var(--md-sys-color-on-surface); white-space: nowrap; overflow: hidden; text-overflow: ellipsis;" title="{s}">{s}</h3>
                \\        <span style="font-size: 0.85rem; color: var(--md-sys-color-on-surface-variant); font-weight: 500;">{s}</span>
                \\        <p style="margin: 4px 0 0 0; font-size: 0.85rem; color: var(--md-sys-color-outline); display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; min-height: 2.4em; line-height: 1.2;" title="{s}">{s}</p>
                \\    </div>
                \\</div>
                , .{ a.uuid, cover_html, a.name, a.name, photo_count_text, desc, desc }
            );
            try html.appendSlice(alloc, card_html);
        }
    }

    try html.appendSlice(alloc, part3);

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

    const template = @embedFile("../../album_detail_gen.html");

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
        avatar_html = try std.fmt.allocPrint(alloc,
            "<img src=\"/avatars/{s}.{s}\" class=\"md-header-logout-icon-btn\" style=\"border-radius: 50%; object-fit: cover; cursor: pointer; padding: 0; width: 40px; height: 40px;\" onclick=\"openProfileModal()\" alt=\"Profile\">",
            .{ username, ext }
        );
    } else {
        avatar_html = 
            \\<button class="md-header-logout-icon-btn" style="border-radius: 50%; background: var(--md-sys-color-primary-container); color: var(--md-sys-color-on-primary-container); font-weight: 500;" onclick="openProfileModal()" title="Profile">
            \\    <svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>
            \\</button>
        ;
    }

    const admin_btn = if (is_admin) 
        \\      <a href="/users" class="md-header-logout-icon-btn" title="User Management" aria-label="User Management">
        \\          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor">
        \\              <path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.06-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.05-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.56-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22l-1.92 3.32c-.12.22-.07.49-.12.61l2.03 1.58c-.04.3-.06.61-.06.94s.02.64.06.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .43-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.49-.12-.61l-2.03-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/>
        \\          </svg>
        \\      </a>
    else "";

    const logout_html = try std.fmt.allocPrint(alloc,
        \\  <div style="display: flex; align-items: center; gap: 8px;">
        \\{s}
        \\{s}
        \\      <form method="POST" action="/logout" style="margin: 0;">
        \\          <button type="submit" class="md-header-logout-icon-btn" title="Logout" aria-label="Logout">
        \\              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
        \\                  <path d="M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h8v-2H4V5z"/>
        \\              </svg>
        \\          </button>
        \\      </form>
        \\  </div>
        , .{ admin_btn, avatar_html }
    );

    const selection_actions_html =
        \\  <div id="selection-actions" class="selection-actions-container" style="display: none;">
        \\      <button class="md-selection-icon-btn" onclick="bulkDownload()" title="Download selected" aria-label="Download selected">
        \\          <svg viewBox="0 0 24 24"><path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM17 13l-5 5-5-5h3V9h4v4h3z"/></svg>
        \\      </button>
        \\      <button class="md-selection-icon-btn" id="bulk-add-to-album-btn" onclick="openBulkAddToAlbum()" title="Add to album" aria-label="Add to album">
        \\          <svg viewBox="0 0 24 24"><path fill="currentColor" d="M20 6h-8l-2-2H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm-1 8h-3v3h-2v-3h-3v-2h3V9h2v3h3v2z"/></svg>
        \\      </button>
        \\      <button class="md-selection-icon-btn" onclick="bulkDelete()" title="Delete selected" aria-label="Delete selected" style="color: var(--md-sys-color-error, #ba1a1a);">
        \\          <svg viewBox="0 0 24 24"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>
        \\      </button>
        \\  </div>
    ;

    const actions_combined = try std.fmt.allocPrint(alloc, "{s}{s}", .{ logout_html, selection_actions_html });

    // 4. Photo Grid HTML
    var photos_html = std.ArrayList(u8).empty;
    for (photos, 0..) |r, idx| {
        const fw: f64 = if (r.width) |w| @floatFromInt(w) else 600.0;
        const fh: f64 = if (r.height) |h| @floatFromInt(h) else 400.0;
        const raw_ratio = fw / fh;
        const ratio = if (raw_ratio > 0.1 and raw_ratio < 10.0) raw_ratio else 1.5;

        const loading_attr = if (idx < 12) "" else " loading=\"lazy\"";
        const priority_attr = if (idx == 0) " fetchpriority=\"high\"" else "";

        const ym = getDisplayYearMonth(r);
        const is_video = std.mem.eql(u8, r.extension, "mp4") or
                         std.mem.eql(u8, r.extension, "mov") or
                         std.mem.eql(u8, r.extension, "m4v") or
                         std.mem.eql(u8, r.extension, "webm") or
                         std.mem.eql(u8, r.extension, "avi");

        const card = if (is_video)
            try std.fmt.allocPrint(alloc,
                \\        <div class="card video-card" data-uuid="{s}" data-year="{s}" data-month="{s}" style="flex:{d:.4} 1 calc({d:.4} * var(--target-h));" onclick="openLightbox('/previews/{s}.{s}')">
                \\            <button class="card-overflow-btn" aria-label="More options" onclick="toggleMenu(event, '{s}', '{s}')">
                \\                <svg viewBox="0 0 24 24"><path d="M12 8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm0 2c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/></svg>
                \\            </button>
                \\            <div class="card-select-checkbox" onclick="toggleSelect(event)">
                \\                <svg viewBox="0 0 24 24"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z"/></svg>
                \\            </div>
                \\            <div class="card-video-play-overlay">
                \\                <svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>
                \\            </div>
                \\            <img src="/thumbnails/{s}.{s}" alt="{s}"{s}{s}>
                \\            <p>{s}</p>
                \\        </div>
                \\
            , .{ r.uuid, ym.year, ym.month, ratio, ratio, r.uuid, r.extension, r.uuid, r.extension, r.uuid, r.extension, r.filename, loading_attr, priority_attr, r.filename })
        else
            try std.fmt.allocPrint(alloc,
                \\        <div class="card" data-uuid="{s}" data-year="{s}" data-month="{s}" style="flex:{d:.4} 1 calc({d:.4} * var(--target-h));" onclick="openLightbox('/previews/{s}.{s}')">
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
            , .{ r.uuid, ym.year, ym.month, ratio, ratio, r.uuid, r.extension, r.uuid, r.extension, r.uuid, r.extension, r.filename, loading_attr, priority_attr, r.filename });
        try photos_html.appendSlice(alloc, card);
    }

    if (photos.len == 0) {
        try photos_html.appendSlice(alloc, 
            \\<p style="text-align: center; width: 100%; color: var(--md-sys-color-on-surface-variant); padding: 48px 0;">No photos in this album yet.</p>
        );
    } else {
        try photos_html.appendSlice(alloc, "        <div class=\"gallery-spacer\"></div>\n");
    }

    // Replace all placeholders
    var result_html: []const u8 = template;
    
    // Replace <!-- ALBUM_NAME -->
    result_html = try replacePlaceholder(alloc, result_html, "<!-- ALBUM_NAME -->", album.name);
    // Replace <!-- ALBUM_NAME_HEADER -->
    result_html = try replacePlaceholder(alloc, result_html, "<!-- ALBUM_NAME_HEADER -->", album.name);
    // Replace <!-- ALBUM_DESC_HEADER -->
    result_html = try replacePlaceholder(alloc, result_html, "<!-- ALBUM_DESC_HEADER -->", album.description orelse "");
    // Replace <!-- GALLERY_LOGOUT -->
    result_html = try replacePlaceholder(alloc, result_html, "<!-- GALLERY_LOGOUT -->", actions_combined);
    // Replace <!-- ALBUM_PHOTOS_CONTENT -->
    result_html = try replacePlaceholder(alloc, result_html, "<!-- ALBUM_PHOTOS_CONTENT -->", photos_html.items);
    // Replace <!-- SHARED_MODALS -->
    result_html = try replacePlaceholder(alloc, result_html, "<!-- SHARED_MODALS -->", shared_modals_html);
    
    // Inject dynamic style tag (prepend to LCP_PRELOAD or replace LCP_PRELOAD)
    const combined_preload_style = try std.fmt.allocPrint(alloc, "{s}{s}", .{ dynamic_style, lcp_tag });
    result_html = try replacePlaceholder(alloc, result_html, "<!-- LCP_PRELOAD -->", combined_preload_style);

    const duplicated = try std.heap.page_allocator.dupe(u8, result_html);
    return duplicated;
}

fn replacePlaceholder(alloc: std.mem.Allocator, input: []const u8, target: []const u8, replacement: []const u8) ![]const u8 {
    const size = std.mem.replacementSize(u8, input, target, replacement);
    const output = try alloc.alloc(u8, size);
    _ = std.mem.replace(u8, input, target, replacement, output);
    return output;
}
