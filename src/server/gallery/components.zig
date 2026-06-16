const std = @import("std");
const db = @import("../../db.zig");

pub const YearMonth = struct {
    year: []const u8,
    month: []const u8,
};

pub fn getDisplayYearMonth(r: db.PhotoRecord) YearMonth {
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
    return .{ .year = "0000", .month = "00" };
}

pub fn writeEscapedHtml(writer: anytype, input: []const u8) !void {
    for (input) |c| {
        switch (c) {
            '&' => try writer.writeAll("&amp;"),
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '"' => try writer.writeAll("&quot;"),
            '\'' => try writer.writeAll("&#x27;"),
            else => try writer.writeByte(c),
        }
    }
}

pub fn renderMediaCard(writer: anytype, r: db.PhotoRecord, idx: usize) !void {
    const fw: f64 = if (r.width) |w| @floatFromInt(w) else 600.0;
    const fh: f64 = if (r.height) |h| @floatFromInt(h) else 400.0;
    const raw_ratio = fw / fh;
    const ratio = if (raw_ratio > 0.1 and raw_ratio < 10.0) raw_ratio else 1.5;

    const loading_attr = if (idx < 12) "" else " loading=\"lazy\"";
    const priority_attr = if (idx < 4) " fetchpriority=\"high\"" else "";

    const ym = getDisplayYearMonth(r);
    const is_video = std.mem.eql(u8, r.extension, "mp4") or
                     std.mem.eql(u8, r.extension, "mov") or
                     std.mem.eql(u8, r.extension, "m4v") or
                     std.mem.eql(u8, r.extension, "webm") or
                     std.mem.eql(u8, r.extension, "avi");

    const shooting_date_str = r.shooting_date orelse "";

    if (is_video) {
        try writer.print(
            \\        <div class="card video-card" data-uuid="{s}" data-year="{s}" data-month="{s}" data-date="{s}" style="flex:{d:.4} 1 calc({d:.4} * var(--target-h));" 
            \\             :class="{{ 'selected': selectedPhotos.includes('{s}'), 'menu-open': activeMenuPhoto === '{s}' }}" 
            \\             @click="selectedPhotos.length > 0 ? toggleSelection('{s}') : openLightbox('/previews/{s}.{s}')">
            \\            <button class="card-overflow-btn" aria-label="More options" @click.stop.prevent="toggleMenu('{s}', $event)">
            \\                <svg viewBox="0 0 24 24"><path d="M12 8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm0 2c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/></svg>
            \\            </button>
            \\            <div class="card-select-checkbox" @click.stop.prevent="toggleSelection('{s}')">
            \\                <svg viewBox="0 0 24 24"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z"/></svg>
            \\            </div>
            \\            <div class="card-video-play-overlay">
            \\                <svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>
            \\            </div>
            \\            <img src="/thumbnails/{s}.{s}" alt="
        , .{ r.uuid, ym.year, ym.month, shooting_date_str, ratio, ratio, r.uuid, r.uuid, r.uuid, r.uuid, r.extension, r.uuid, r.uuid, r.uuid, r.extension });

        try writeEscapedHtml(writer, r.filename);

        try writer.print(
            \\"{s}{s}>
            \\            <p>
        , .{ loading_attr, priority_attr });

        try writeEscapedHtml(writer, r.filename);

        try writer.writeAll(
            \\</p>
            \\        </div>
            \\
        );
    } else {
        try writer.print(
            \\        <div class="card" data-uuid="{s}" data-year="{s}" data-month="{s}" data-date="{s}" style="flex:{d:.4} 1 calc({d:.4} * var(--target-h));" 
            \\             :class="{{ 'selected': selectedPhotos.includes('{s}'), 'menu-open': activeMenuPhoto === '{s}' }}" 
            \\             @click="selectedPhotos.length > 0 ? toggleSelection('{s}') : openLightbox('/previews/{s}.{s}')">
            \\            <button class="card-overflow-btn" aria-label="More options" @click.stop.prevent="toggleMenu('{s}', $event)">
            \\                <svg viewBox="0 0 24 24"><path d="M12 8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm0 2c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/></svg>
            \\            </button>
            \\            <div class="card-select-checkbox" @click.stop.prevent="toggleSelection('{s}')">
            \\                <svg viewBox="0 0 24 24"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z"/></svg>
            \\            </div>
            \\            <img src="/thumbnails/{s}.{s}" alt="
        , .{ r.uuid, ym.year, ym.month, shooting_date_str, ratio, ratio, r.uuid, r.uuid, r.uuid, r.uuid, r.extension, r.uuid, r.uuid, r.uuid, r.extension });

        try writeEscapedHtml(writer, r.filename);

        try writer.print(
            \\"{s}{s}>
            \\            <p>
        , .{ loading_attr, priority_attr });

        try writeEscapedHtml(writer, r.filename);

        try writer.writeAll(
            \\</p>
            \\        </div>
            \\
        );
    }
}

pub fn renderAdminBtn(writer: anytype) !void {
    try writer.writeAll(
        \\      <a href="/users" class="md-header-logout-icon-btn" title="User Management" aria-label="User Management">
        \\          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor">
        \\              <path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.06-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.05-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.56-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22l-1.92 3.32c-.12.22-.07.49-.12.61l2.03 1.58c-.04.3-.06.61-.06.94s.02.64.06.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .43-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.49-.12-.61l-2.03-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/>
        \\          </svg>
        \\      </a>
        \\
    );
}

pub fn renderAvatarDefault(writer: anytype) !void {
    try writer.writeAll(
        \\<button class="md-header-logout-icon-btn" style="border-radius: 50%; background: var(--md-sys-color-primary-container); color: var(--md-sys-color-on-primary-container); font-weight: 500;" hx-get="/api/profile-modal" hx-target="body" hx-swap="beforeend" title="Profile">
        \\    <svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>
        \\</button>
        \\
    );
}

pub fn renderAvatarImg(writer: anytype, username: []const u8, ext: []const u8) !void {
    try writer.print(
        \\<img src="/avatars/{s}.{s}" class="md-header-logout-icon-btn" style="border-radius: 50%; object-fit: cover; cursor: pointer; padding: 0; width: 40px; height: 40px;" hx-get="/api/profile-modal" hx-target="body" hx-swap="beforeend" alt="Profile">
        \\
    , .{ username, ext });
}

pub fn renderLogout(writer: anytype, is_admin: bool, username: []const u8, avatar_ext: ?[]const u8) !void {
    try writer.writeAll("  <div style=\"display: flex; align-items: center; gap: 8px;\">\n");
    if (is_admin) {
        try renderAdminBtn(writer);
    }
    if (avatar_ext) |ext| {
        if (ext.len > 0) {
            try renderAvatarImg(writer, username, ext);
        } else {
            try renderAvatarDefault(writer);
        }
    } else {
        try renderAvatarDefault(writer);
    }
    try writer.writeAll(
        \\      <button type="button" class="md-header-logout-icon-btn" hx-post="/logout" hx-target="body" title="Logout" aria-label="Logout">
        \\          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
        \\              <path d="M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h8v-2H4V5z"/>
        \\          </svg>
        \\      </button>
        \\  </div>
        \\
    );
}

pub fn renderSharedModals(writer: anytype) !void {
    try writer.writeAll(
        \\    <!-- Global Overflow Menu -->
        \\    <div id="global-menu" class="md-menu" :class="{ 'active': activeMenuPhoto !== null }" x-show="activeMenuPhoto !== null" @click.away="closeMenu()" x-transition x-cloak>
        \\        <button class="md-menu-item" id="menu-metadata" @click="openMetadataModal(); closeMenu()">
        \\            <svg viewBox="0 0 24 24"><path fill="currentColor" d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/></svg>
        \\            <span>View metadata</span>
        \\        </button>
        \\        <button class="md-menu-item" id="menu-change-date" @click="openChangeDateModal(); closeMenu()">
        \\            <svg viewBox="0 0 24 24"><path fill="currentColor" d="M19 3h-1V1h-2v2H8V1H6v2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16H5V8h14v11zM7 10h5v5H7v-5z"/></svg>
        \\            <span>Change Date/Time</span>
        \\        </button>
        \\        <button class="md-menu-item" id="menu-download" @click="bulkDownload(); closeMenu()">
        \\            <svg viewBox="0 0 24 24"><path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM17 13l-5 5-5-5h3V9h4v4h3z"/></svg>
        \\            <span>Download</span>
        \\        </button>
        \\        <button class="md-menu-item" id="menu-add-to-album" @click="openAddToAlbumModal(); closeMenu()">
        \\            <svg viewBox="0 0 24 24"><path fill="currentColor" d="M20 6h-8l-2-2H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm-1 8h-3v3h-2v-3h-3v-2h3V9h2v3h3v2z"/></svg>
        \\            <span>Add to album</span>
        \\        </button>
        \\        <button class="md-menu-item md-menu-item--danger" id="menu-delete" hx-post="/delete-batch" :hx-vals='`js:{uuids: "${activeMenuPhoto}"}`' hx-swap="none" @click="closeMenu(); if(!confirm('Are you sure you want to delete this photo?')) { event.preventDefault(); event.stopPropagation(); }">
        \\            <svg viewBox="0 0 24 24"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>
        \\            <span>Delete</span>
        \\        </button>
        \\    </div>
        \\
        \\    <!-- Metadata Modal -->
        \\    <div id="metadata-modal" class="lightbox" :class="{ 'active': modals.metadata }" x-show="modals.metadata" x-transition x-cloak @click="closeAllModals()">
        \\        <div class="modal-content" style="background: var(--md-sys-color-surface-container); padding: 24px; border-radius: 28px; width: 500px; max-width: 90%; max-height: 80vh; display: flex; flex-direction: column; box-shadow: 0 4px 12px rgba(0,0,0,0.15);" @click.stop>
        \\            <h2 style="margin-top: 0; color: var(--md-sys-color-on-surface); margin-bottom: 16px;">Photo Metadata</h2>
        \\            <div id="metadata-list" style="overflow-y: auto; flex: 1; margin-bottom: 24px; display: flex; flex-direction: column; gap: 8px;">
        \\                <div x-html="metadataHtml" hx-get="/api/photos/null/metadata" x-bind:hx-get="`/api/photos/${activePhoto}/metadata`" hx-trigger="loadMetadata from:body">
        \\                    Loading...
        \\                </div>
        \\            </div>
        \\            <div style="text-align: right;">
        \\                <button class="md-menu-item" style="display: inline-block; width: auto; background: var(--md-sys-color-primary); color: var(--md-sys-color-on-primary); border: none; padding: 10px 24px; border-radius: 20px; font-weight: 500; cursor: pointer;" @click="closeAllModals()">Close</button>
        \\            </div>
        \\        </div>
        \\    </div>
        \\
        \\    <!-- Album Selection Modal -->
        \\    <div id="album-select-modal" class="lightbox" :class="{ 'active': modals.addToAlbum }" x-show="modals.addToAlbum" x-transition x-cloak @click="closeAllModals()">
        \\        <div class="modal-content" style="background: var(--md-sys-color-surface-container); padding: 24px; border-radius: 28px; width: 400px; max-width: 90%; box-shadow: 0 4px 12px rgba(0,0,0,0.15);" @click.stop>
        \\            <h3 style="margin-top: 0; color: var(--md-sys-color-on-surface); margin-bottom: 16px;">Add to Album</h3>
        \\            <div id="album-list-container" style="overflow-y: auto; max-height: 300px; margin-bottom: 24px; display: flex; flex-direction: column; gap: 8px;" hx-get="/api/albums" hx-trigger="loadAlbums from:body">
        \\                Loading...
        \\            </div>
        \\            <div style="text-align: right;">
        \\                <button class="md-menu-item" style="display: inline-block; width: auto; background: transparent; color: var(--md-sys-color-primary); border: none; padding: 10px 16px; border-radius: 20px; font-weight: 500; cursor: pointer;" @click="closeAllModals()">Cancel</button>
        \\                <button id="submit-add-to-album" class="md-menu-item" style="display: inline-block; width: auto; background: var(--md-sys-color-primary); color: var(--md-sys-color-on-primary); border: none; padding: 10px 24px; border-radius: 20px; font-weight: 500; cursor: pointer; margin-left: 8px;">Add</button>
        \\            </div>
        \\        </div>
        \\    </div>
        \\
        \\    <!-- Change Date Modal -->
        \\    <div id="change-date-modal" class="lightbox" :class="{ 'active': modals.changeDate }" x-show="modals.changeDate" x-transition x-cloak @click="closeAllModals()">
        \\        <div class="modal-content" style="background: var(--md-sys-color-surface-container); padding: 24px; border-radius: 28px; width: 350px; max-width: 90%; box-shadow: 0 4px 12px rgba(0,0,0,0.15);" @click.stop>
        \\            <h3 style="margin-top: 0; color: var(--md-sys-color-on-surface); margin-bottom: 16px;">Change Date/Time</h3>
        \\            <form hx-ext="json-enc" x-bind:hx-put="`/api/photos/${activePhoto}/date`" @submit="closeAllModals(); setTimeout(() => window.location.reload(), 200);">
        \\                <input type="datetime-local" step="1" id="change-date-input" name="date" style="width: 100%; padding: 12px; border-radius: 12px; border: 1px solid var(--md-sys-color-outline); background: var(--md-sys-color-surface); color: var(--md-sys-color-on-surface); font-family: inherit; font-size: 16px; margin-bottom: 24px; box-sizing: border-box;" />
        \\                <div style="text-align: right;">
        \\                    <button type="button" class="md-menu-item" style="display: inline-block; width: auto; background: transparent; color: var(--md-sys-color-primary); border: none; padding: 10px 16px; border-radius: 20px; font-weight: 500; cursor: pointer; margin-right: 8px;" @click="closeAllModals()">Cancel</button>
        \\                    <button type="submit" class="md-menu-item" style="display: inline-block; width: auto; background: var(--md-sys-color-primary); color: var(--md-sys-color-on-primary); border: none; padding: 10px 24px; border-radius: 20px; font-weight: 500; cursor: pointer;">Save</button>
        \\                </div>
        \\            </form>
        \\        </div>
        \\    </div>
        \\
        \\    <div id="toast" class="toast"></div>
        \\
    );
}

pub fn renderSelectionActions(writer: anytype) !void {
    try writer.writeAll(
        \\  <div id="selection-actions" class="selection-actions-container" x-show="selectedPhotos.length > 0" x-transition x-cloak>
        \\      <button class="md-selection-icon-btn" @click="bulkDownload()" title="Download selected" aria-label="Download selected">
        \\          <svg viewBox="0 0 24 24"><path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM17 13l-5 5-5-5h3V9h4v4h3z"/></svg>
        \\      </button>
        \\      <button class="md-selection-icon-btn" id="bulk-add-to-album-btn" @click="openAddToAlbumModal()" title="Add to album" aria-label="Add to album">
        \\          <svg viewBox="0 0 24 24"><path fill="currentColor" d="M20 6h-8l-2-2H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm-1 8h-3v3h-2v-3h-3v-2h3V9h2v3h3v2z"/></svg>
        \\      </button>
        \\      <button class="md-selection-icon-btn" hx-post="/delete-batch" hx-vals='js:{uuids: selectedPhotos.join(",")}' hx-swap="none" title="Delete selected" aria-label="Delete selected" style="color: var(--md-sys-color-error, #ba1a1a);" @click="if(!confirm(`Are you sure you want to delete ${selectedPhotos.length} photos?`)) { event.preventDefault(); event.stopPropagation(); }">
        \\          <svg viewBox="0 0 24 24"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>
        \\      </button>
        \\  </div>
        \\
    );
}

pub fn renderAlbumCard(
    writer: anytype,
    uuid: []const u8,
    name: []const u8,
    photo_count: i32,
    desc: ?[]const u8,
    cover_uuid: ?[]const u8,
    cover_ext: ?[]const u8,
    idx: usize,
) !void {
    const loading_attr = if (idx < 12) "" else " loading=\"lazy\"";
    const priority_attr = if (idx < 4) " fetchpriority=\"high\"" else "";

    try writer.print(
        \\<div class="album-card" @click="window.location.href='/albums/{s}'" style="width: 220px; background: var(--md-sys-color-surface-container); border-radius: 16px; box-shadow: 0 2px 6px rgba(0,0,0,0.1); cursor: pointer; transition: transform 0.2s, box-shadow 0.2s; overflow: hidden; display: flex; flex-direction: column;">
        \\
    , .{uuid});

    if (cover_uuid) |cu| {
        const ext = cover_ext orelse "jpg";
        try writer.print(
            \\    <img src="/thumbnails/{s}.{s}" alt="
        , .{ cu, ext });
        try writeEscapedHtml(writer, name);
        try writer.print(
            \\" style="width: 100%; height: 160px; object-fit: cover; border-radius: 12px 12px 0 0;"{s}{s}>
            \\
        , .{ loading_attr, priority_attr });
    } else {
        try writer.writeAll(
            \\    <div style="width: 100%; height: 160px; background: var(--md-sys-color-surface-container-high); display: flex; align-items: center; justify-content: center; border-radius: 12px 12px 0 0; color: var(--md-sys-color-primary);">
            \\        <svg viewBox="0 0 24 24" fill="currentColor" width="48" height="48">
            \\            <path d="M22 16V4c0-1.1-.9-2-2-2H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2zm-11-4 2.03 2.71L16 11l4 5H8l3-4zM2 6v14c0 1.1.9 2 2 2h14v-2H4V6H2z"/>
            \\        </svg>
            \\    </div>
            \\
        );
    }

    try writer.writeAll("    <div style=\"padding: 16px; display: flex; flex-direction: column; gap: 4px;\">\n");
    try writer.writeAll("        <h3 style=\"margin: 0; font-size: 1.1rem; font-weight: 600; color: var(--md-sys-color-on-surface); white-space: nowrap; overflow: hidden; text-overflow: ellipsis;\" title=\"");
    try writeEscapedHtml(writer, name);
    try writer.writeAll("\">");
    try writeEscapedHtml(writer, name);
    try writer.writeAll("</h3>\n");

    if (photo_count == 1) {
        try writer.writeAll("        <span style=\"font-size: 0.85rem; color: var(--md-sys-color-on-surface-variant); font-weight: 500;\">1 photo</span>\n");
    } else {
        try writer.print("        <span style=\"font-size: 0.85rem; color: var(--md-sys-color-on-surface-variant); font-weight: 500;\">{d} photos</span>\n", .{photo_count});
    }

    try writer.writeAll("        <p style=\"margin: 4px 0 0 0; font-size: 0.85rem; color: var(--md-sys-color-outline); display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; min-height: 2.4em; line-height: 1.2;\" title=\"");
    if (desc) |d| {
        try writeEscapedHtml(writer, d);
    }
    try writer.writeAll("\">");
    if (desc) |d| {
        try writeEscapedHtml(writer, d);
    }
    try writer.writeAll("</p>\n");

    try writer.writeAll(
        \\    </div>
        \\</div>
        \\
    );
}

pub fn renderAlbumEmpty(writer: anytype) !void {
    try writer.writeAll(
        \\<p style="text-align: center; width: 100%; color: var(--md-sys-color-on-surface-variant); padding: 48px 0;">No albums yet.</p>
        \\
    );
}

pub fn renderAlbumPhotosEmpty(writer: anytype) !void {
    try writer.writeAll(
        \\<p style="text-align: center; width: 100%; color: var(--md-sys-color-on-surface-variant); padding: 48px 0;">No photos in this album yet.</p>
        \\
    );
}

pub fn renderGallerySpacer(writer: anytype) !void {
    try writer.writeAll(
        \\        <div class="gallery-spacer"></div>
        \\
    );
}

pub fn renderFilterSelect(writer: anytype, years: [][]const u8) !void {
    try writer.writeAll(
        \\<div class="filter-select-container"><select id="filter-year" class="md-filter-select" x-model="filterYear" aria-label="Filter by Year"><option value="all">All Years</option>
        \\
    );
    for (years) |y| {
        try writer.print("<option value=\"{s}\">{s}</option>\n", .{ y, y });
    }
    try writer.writeAll(
        \\</select></div>
        \\
    );
}

pub fn renderDynamicStyle(writer: anytype, thumbnail_height: i32) !void {
    try writer.print("<style>:root {{ --target-h: {d}px; }}</style>\n", .{thumbnail_height});
}

pub fn renderPreloadTag(writer: anytype, uuid: []const u8, ext: []const u8) !void {
    try writer.print("<link rel=\"preload\" as=\"image\" href=\"/thumbnails/{s}.{s}\" fetchpriority=\"high\">\n", .{ uuid, ext });
}

pub fn renderProfileModal(writer: anytype, username: []const u8, real_name: []const u8) !void {
    try writer.print(
        \\<!-- Profile Modal -->
        \\<div id="profile-modal" class="lightbox" :class="{{ 'active': open }}" x-data="{{ open: true }}" x-show="open" x-init="$watch('open', v => {{ if(!v) setTimeout(() => $el.remove(), 300) }})" x-transition x-cloak @click="open = false">
        \\    <div class="modal-content" style="background: var(--md-sys-color-surface-container); padding: 24px; border-radius: 28px; width: 400px; max-width: 90%; box-shadow: 0 4px 12px rgba(0,0,0,0.15);" @click.stop>
        \\        <h2 style="margin-top: 0; color: var(--md-sys-color-on-surface); margin-bottom: 16px;">My Profile</h2>
        \\        <form hx-put="/api/users/me" hx-ext="json-enc" @submit="open = false; setTimeout(() => window.location.reload(), 200);">
        \\            <div style="margin-bottom: 16px;">
        \\                <label style="display: block; font-weight: 500; margin-bottom: 4px;">Username</label>
        \\                <input type="text" id="profile-username" name="username" value="{s}" readonly autocomplete="username" style="width: 100%; border: 1px solid var(--md-sys-color-outline); border-radius: 8px; padding: 12px; box-sizing: border-box; background: transparent; opacity: 0.7; color: inherit;" tabindex="-1">
        \\            </div>
        \\            <div style="margin-bottom: 16px;">
        \\                <label style="display: block; font-weight: 500; margin-bottom: 4px;">Real Name</label>
        \\                <input type="text" id="profile-real-name" name="real_name" value="
    , .{ username });

    try writeEscapedHtml(writer, real_name);

    try writer.writeAll(
        \\" autocomplete="name" style="width: 100%; border: 1px solid var(--md-sys-color-outline); border-radius: 8px; padding: 12px; box-sizing: border-box; background: transparent; color: inherit;">
        \\            </div>
        \\            <div style="margin-bottom: 24px;">
        \\                <label style="display: block; font-weight: 500; margin-bottom: 4px;">New Password (leave blank to keep current)</label>
        \\                <input type="password" id="profile-password" name="password" autocomplete="new-password" style="width: 100%; border: 1px solid var(--md-sys-color-outline); border-radius: 8px; padding: 12px; box-sizing: border-box; background: transparent; color: inherit;">
        \\            </div>
        \\            <div style="text-align: right;">
        \\                <button type="button" class="md-menu-item" style="display: inline-block; width: auto; margin-right: 8px; background: transparent; border: none; cursor: pointer; color: var(--md-sys-color-on-surface);" @click="open = false">Cancel</button>
        \\                <button type="submit" style="background: var(--md-sys-color-primary); color: var(--md-sys-color-on-primary); border: none; padding: 10px 24px; border-radius: 20px; font-weight: 500; cursor: pointer;">Save</button>
        \\            </div>
        \\        </form>
        \\    </div>
        \\</div>
        \\
    );
}
