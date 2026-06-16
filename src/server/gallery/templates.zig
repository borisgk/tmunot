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
            \\        <div class="card video-card" x-data="{{ hovered: false }}" @mouseenter="hovered = true" @mouseleave="hovered = false" data-uuid="{s}" data-year="{s}" data-month="{s}" data-date="{s}" style="flex:{d:.4} 1 calc({d:.4} * var(--target-h));" 
            \\             :class="{{ 'selected': selectedPhotos.includes('{s}'), 'menu-open': activeMenuPhoto === '{s}' }}" 
            \\             @click="selectedPhotos.length > 0 ? toggleSelection('{s}') : openLightbox('/previews/{s}.{s}')">
            \\            <template x-if="hovered">
            \\                <video src="/hover_previews/{s}.mp4" autoplay loop muted playsinline style="position: absolute; top: 0; left: 0; width: 100%; height: 100%; object-fit: cover; z-index: 1; border-radius: inherit; pointer-events: none;"></video>
            \\            </template>
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
        , .{ r.uuid, ym.year, ym.month, shooting_date_str, ratio, ratio, r.uuid, r.uuid, r.uuid, r.uuid, r.extension, r.uuid, r.uuid, r.uuid, r.uuid, r.extension });

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
        \\        <div class="modal-content" style="background: var(--md-sys-color-surface-container); padding: 24px; border-radius: 28px; width: 900px; max-width: 95%; max-height: 90vh; display: flex; flex-direction: column; box-shadow: 0 4px 12px rgba(0,0,0,0.15);" @click.stop>
        \\            
        \\            <!-- Header -->
        \\            <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 16px; border-bottom: 1px solid var(--md-sys-color-outline-variant); padding-bottom: 16px;">
        \\                <div>
        \\                    <h2 style="margin: 0; color: var(--md-sys-color-on-surface); font-size: 1.5rem;" x-text="metadataFilename || 'Photo Metadata'"></h2>
        \\                    <p style="margin: 4px 0 0 0; font-size: 0.875rem; color: var(--md-sys-color-on-surface-variant);">Details</p>
        \\                </div>
        \\                <button class="md-menu-item" style="display: inline-block; width: auto; background: transparent; color: var(--md-sys-color-on-surface-variant); border: none; padding: 8px; border-radius: 50%; cursor: pointer;" @click="closeAllModals()" aria-label="Close">
        \\                    <svg viewBox="0 0 24 24" width="24" height="24"><path fill="currentColor" d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>
        \\                </button>
        \\            </div>
        \\            
        \\            <!-- Content -->
        \\            <div style="display: flex; flex-wrap: wrap; gap: 24px; overflow-y: auto; flex: 1; padding-right: 8px;">
        \\                
        \\                <!-- Left Column: Large Thumbnail -->
        \\                <div style="flex: 1 1 400px; display: flex; flex-direction: column; align-items: center; justify-content: flex-start; position: sticky; top: 0; align-self: flex-start;">
        \\                    <template x-if="metadataIsVideo && metadataVideoSrc">
        \\                        <video :src="metadataVideoSrc" controls autoplay loop muted style="width: 100%; max-height: 60vh; object-fit: contain; border-radius: 12px; background: var(--md-sys-color-surface-variant); box-shadow: 0 2px 8px rgba(0,0,0,0.1);"></video>
        \\                    </template>
        \\                    <template x-if="!metadataIsVideo && metadataThumbnail">
        \\                        <img :src="metadataThumbnail" style="width: 100%; max-height: 60vh; object-fit: contain; border-radius: 12px; background: var(--md-sys-color-surface-variant); box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
        \\                    </template>
        \\                </div>
        \\                
        \\                <!-- Right Column: Metadata Table -->
        \\                <div id="metadata-list" style="flex: 1 1 300px; display: flex; flex-direction: column;">
        \\                    <template x-if="!metadata">
        \\                        <div style="display: flex; justify-content: center; padding: 32px; color: var(--md-sys-color-on-surface-variant);">
        \\                            Loading metadata...
        \\                        </div>
        \\                    </template>
        \\                    <template x-if="metadata && metadata.error">
        \\                        <div style="color: var(--md-sys-color-error); padding: 16px; background: var(--md-sys-color-error-container); border-radius: 12px;" x-text="metadata.error"></div>
        \\                    </template>
        \\                    <template x-if="metadata && !metadata.error">
        \\                        <table style="width: 100%; border-collapse: collapse; font-size: 0.875rem;">
        \\                            <tbody style="display: flex; flex-direction: column; gap: 4px;">
        \\                                <template x-for="(value, key) in metadata" :key="key">
        \\                                    <template x-if="value !== null && key !== 'uuid'">
        \\                                        <tr style="display: flex; border-bottom: 1px solid var(--md-sys-color-surface-variant); padding: 8px 4px;">
        \\                                            <th style="flex: 0 0 40%; text-align: left; font-weight: 500; color: var(--md-sys-color-on-surface-variant); padding-right: 16px;" x-text="key"></th>
        \\                                            <td style="flex: 1; color: var(--md-sys-color-on-surface); word-break: break-word;" x-text="value"></td>
        \\                                        </tr>
        \\                                    </template>
        \\                                </template>
        \\                            </tbody>
        \\                        </table>
        \\                    </template>
        \\                </div>
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
        \\                <button id="submit-add-to-album" class="md-menu-item" style="display: inline-block; width: auto; background: var(--md-sys-color-primary); color: var(--md-sys-color-on-primary); border: none; padding: 10px 24px; border-radius: 20px; font-weight: 500; cursor: pointer; margin-left: 8px;" @click="addSelectedPhotosToAlbum()">Add</button>
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

pub fn renderFilterSelect(writer: anytype, years: [][]const u8, active_year: ?[]const u8) !void {
    try writer.writeAll(
        \\<div class="filter-select-container"><select id="filter-year" class="md-filter-select" name="year" hx-get="/" hx-target="#gallery-grid" hx-swap="innerHTML" hx-push-url="true" x-model="filterYear" aria-label="Filter by Year"><option value="all">All Years</option>
        \\
    );
    for (years) |y| {
        const selected_attr = if (active_year) |ay| (if (std.mem.eql(u8, ay, y)) " selected" else "") else "";
        try writer.print("<option value=\"{s}\"{s}>{s}</option>\n", .{ y, selected_attr, y });
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

pub fn renderUploadHtml(writer: anytype) !void {
    try writer.writeAll(
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\
        \\<head>
        \\    <meta charset="UTF-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\    <title>Upload - Image Gallery</title>
        \\    <link rel="stylesheet" href="/css/styles.css">
        \\    <link rel="stylesheet" href="/css/upload.css">
        \\</head>
        \\
        \\<body class="gallery-body">
        \\    <div class="upload-container" x-data="uploadState">
        \\        <h2 style="display: flex; align-items: baseline; justify-content: center;">Upload Media <span style="font-size: 0.8rem; font-weight: 400; opacity: 0.7; margin-left: 8px;">v0.0.20</span></h2>
        \\        <p class="subtitle">Select or drag and drop your files to upload them to the gallery</p>
        \\
        \\        <div id="dropzone" class="dropzone"
        \\             x-show="queuedFiles.length === 0"
        \\             @click="$refs.fileInput.click()"
        \\             @dragenter.prevent="dragover = true"
        \\             @dragover.prevent="dragover = true"
        \\             @dragleave.prevent="dragover = false"
        \\             @drop.prevent="dragover = false; handleFiles($event.dataTransfer.files)"
        \\             :class="{ 'dragover': dragover }"
        \\             style="cursor: pointer;">
        \\            <svg viewBox="0 0 24 24">
        \\                <path
        \\                    d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM14 13v4h-4v-4H7l5-5 5 5h-3z" />
        \\            </svg>
        \\            <p>Drag and drop media files here</p>
        \\            <span>or click to browse from files</span>
        \\            <input type="file" id="file-input" multiple accept="image/*,video/*" style="display: none;"
        \\                   x-ref="fileInput"
        \\                   @change="handleFiles($event.target.files); $event.target.value = ''">
        \\        </div>
        \\
        \\        <h3 id="staged-title" class="staged-title" x-show="queuedFiles.length > 0" x-cloak>
        \\            Staged Files (<span x-text="queuedFiles.length"></span>)
        \\        </h3>
        \\        <div id="staged-list" class="staged-list" x-show="queuedFiles.length > 0" x-cloak>
        \\            <template x-for="(file, index) in queuedFiles" :key="file.id">
        \\                <div class="staged-item"
        \\                     :class="{ 'processing': file.status === 'processing', 'fade-out': file.status === 'done' }">
        \\                    <div class="staged-item-progress-overlay" :style="`width: ${file.progress}%`"></div>
        \\                    <img :src="file.thumbnail || defaultThumbnail" alt="preview">
        \\                    <div class="staged-item-details">
        \\                        <div class="staged-item-name" x-text="file.name"></div>
        \\                        <div class="staged-item-size" x-text="formatBytes(file.size)"></div>
        \\                    </div>
        \\                    <div class="staged-item-pct" x-text="`${file.progress}%`"></div>
        \\                    <button type="button" class="remove-btn" title="Remove file" @click="removeFile(index)" x-show="!uploading">
        \\                        <svg viewBox="0 0 24 24">
        \\                            <path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/>
        \\                        </svg>
        \\                    </button>
        \\                </div>
        \\            </template>
        \\        </div>
        \\
        \\        <div class="error-message" id="error-message" style="margin-bottom: 1.5rem; text-align: center;" 
        \\             x-show="errorMessage !== ''" x-text="errorMessage" x-cloak></div>
        \\
        \\        <div class="upload-actions">
        \\            <a href="/" class="secondary-btn">Cancel</a>
        \\            <button id="upload-btn" class="primary-btn" :disabled="queuedFiles.length === 0 || uploading" @click="uploadFiles()">Upload</button>
        \\        </div>
        \\    </div>
        \\
        \\    <script src="/js/core.js" defer></script>
        \\    <script src="/js/upload.js" defer></script>
        \\    <script src="/js/alpine.min.js" defer></script>
        \\</body>
        \\
        \\</html>
        \\
    );
}

pub fn renderLoginHtml(writer: anytype, csrf_token: []const u8, error_message: []const u8) !void {
    try writer.print(
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\    <meta charset="UTF-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\    <title>Secure Login</title>
        \\    <link rel="stylesheet" href="/css/styles.css">
        \\</head>
        \\<body class="login-body">
        \\    <div class="login-container">
        \\        <h2>Welcome Back</h2>
        \\        <form id="loginForm" method="POST" action="/login">
        \\            <input type="hidden" name="csrf_token" value="{s}">
        \\            <div class="md-text-field">
        \\                <input type="text" id="username" name="username" required autocomplete="username" placeholder=" ">
        \\                <label for="username">Username</label>
        \\            </div>
        \\            <div class="md-text-field">
        \\                <input type="password" id="password" name="password" required autocomplete="current-password" placeholder=" ">
        \\                <label for="password">Password</label>
        \\            </div>
        \\            <button type="submit" class="submit-btn"><span>Sign In</span></button>
        \\            <div class="error-message" id="errorMessage">
    , .{csrf_token});

    try writeEscapedHtml(writer, error_message);

    try writer.writeAll(
        \\</div>
        \\        </form>
        \\    </div>
        \\</body>
        \\</html>
        \\
    );
}

pub fn renderUsersHtml(writer: anytype) !void {
    try writer.writeAll(
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\    <meta charset="UTF-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\    <title>User Management - Image Gallery</title>
        \\    <link rel="stylesheet" href="/css/styles.css">
        \\    <style>
        \\        .admin-container {
        \\            max-width: 1200px;
        \\            margin: 40px auto;
        \\            padding: 32px;
        \\        }
        \\        .admin-section {
        \\            margin-bottom: 40px;
        \\        }
        \\        .admin-section h2 {
        \\            margin-top: 0;
        \\            border-bottom: 1px solid var(--md-sys-color-outline-variant, #cac4d0);
        \\            padding-bottom: 8px;
        \\        }
        \\        .form-group {
        \\            margin-bottom: 16px;
        \\        }
        \\        .form-group label {
        \\            display: block;
        \\            margin-bottom: 4px;
        \\            font-weight: 500;
        \\        }
        \\        .form-group input {
        \\            width: 100%;
        \\            padding: 12px;
        \\            border-radius: 8px;
        \\            border: 1px solid var(--md-sys-color-outline, #79747e);
        \\            background: transparent;
        \\            color: var(--md-sys-color-on-surface);
        \\            font-family: inherit;
        \\        }
        \\        .form-row {
        \\            display: flex;
        \\            gap: 16px;
        \\        }
        \\        .form-row > .form-group {
        \\            flex: 1;
        \\        }
        \\        .users-grid {
        \\            display: grid;
        \\            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
        \\            gap: 24px;
        \\            margin-top: 24px;
        \\        }
        \\        .user-card {
        \\            background: var(--md-sys-color-surface-container);
        \\            border-radius: var(--md-sys-shape-corner-large);
        \\            padding: 24px;
        \\            display: flex;
        \\            align-items: center;
        \\            gap: 16px;
        \\            position: relative;
        \\            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
        \\        }
        \\        .user-avatar {
        \\            width: 48px;
        \\            height: 48px;
        \\            border-radius: 50%;
        \\            background: var(--md-sys-color-primary-container);
        \\            color: var(--md-sys-color-on-primary-container);
        \\            display: flex;
        \\            align-items: center;
        \\            justify-content: center;
        \\            font-size: 24px;
        \\            font-weight: 500;
        \\            text-transform: uppercase;
        \\        }
        \\        .user-info {
        \\            flex: 1;
        \\            overflow: hidden;
        \\        }
        \\        .user-name {
        \\            font-size: 1.1rem;
        \\            font-weight: 500;
        \\            color: var(--md-sys-color-on-surface);
        \\            white-space: nowrap;
        \\            overflow: hidden;
        \\            text-overflow: ellipsis;
        \\        }
        \\        .user-subtitle {
        \\            font-size: 0.9rem;
        \\            color: var(--md-sys-color-on-surface-variant);
        \\            white-space: nowrap;
        \\            overflow: hidden;
        \\            text-overflow: ellipsis;
        \\        }
        \\        .user-action-btn {
        \\            background: none;
        \\            border: none;
        \\            color: var(--md-sys-color-on-surface-variant);
        \\            cursor: pointer;
        \\            width: 40px;
        \\            height: 40px;
        \\            border-radius: 50%;
        \\            display: flex;
        \\            align-items: center;
        \\            justify-content: center;
        \\            transition: background-color 0.2s;
        \\        }
        \\        .user-action-btn:hover {
        \\            background: var(--md-sys-color-surface-container-high);
        \\        }
        \\        .user-delete-btn {
        \\            color: var(--md-sys-color-error);
        \\        }
        \\        .user-delete-btn:hover {
        \\            background: var(--md-sys-color-error-container);
        \\        }
        \\        .modal-overlay {
        \\            position: fixed;
        \\            top: 0;
        \\            left: 0;
        \\            right: 0;
        \\            bottom: 0;
        \\            background: rgba(0, 0, 0, 0.5);
        \\            display: none;
        \\            align-items: center;
        \\            justify-content: center;
        \\            z-index: 1000;
        \\            opacity: 0;
        \\            transition: opacity 0.2s;
        \\        }
        \\        .modal-overlay.show {
        \\            display: flex;
        \\            opacity: 1;
        \\        }
        \\        .modal-surface {
        \\            background: var(--md-sys-color-surface-container-high);
        \\            border-radius: var(--md-sys-shape-corner-extra-large);
        \\            padding: 32px;
        \\            width: 100%;
        \\            max-width: 400px;
        \\            transform: translateY(20px);
        \\            transition: transform 0.2s;
        \\        }
        \\        .modal-overlay.show .modal-surface {
        \\            transform: translateY(0);
        \\        }
        \\        .modal-surface h2 {
        \\            margin-top: 0;
        \\            margin-bottom: 24px;
        \\            color: var(--md-sys-color-primary);
        \\        }
        \\        .modal-actions {
        \\            display: flex;
        \\            justify-content: flex-end;
        \\            margin-top: 32px;
        \\        }
        \\        .action-btn {
        \\            background: none;
        \\            border: none;
        \\            color: var(--md-sys-color-error, #ba1a1a);
        \\            cursor: pointer;
        \\            font-family: inherit;
        \\            font-weight: 500;
        \\        }
        \\        .action-btn:hover {
        \\            text-decoration: underline;
        \\        }
        \\        .btn-primary {
        \\            background: var(--md-sys-color-primary, #6750a4);
        \\            color: var(--md-sys-color-on-primary, #ffffff);
        \\            border: none;
        \\            padding: 10px 24px;
        \\            border-radius: 20px;
        \\            font-weight: 500;
        \\            cursor: pointer;
        \\            font-family: inherit;
        \\        }
        \\        .btn-primary:hover {
        \\            opacity: 0.9;
        \\        }
        \\        .toast {
        \\            position: fixed;
        \\            bottom: 24px;
        \\            left: 50%;
        \\            transform: translateX(-50%);
        \\            background: var(--md-sys-color-inverse-surface, #313033);
        \\            color: var(--md-sys-color-inverse-on-surface, #f4eff4);
        \\            padding: 12px 24px;
        \\            border-radius: 4px;
        \\            opacity: 0;
        \\            transition: opacity 0.3s;
        \\            pointer-events: none;
        \\        }
        \\        .toast.show {
        \\            opacity: 1;
        \\        }
        \\
        \\    </style>
        \\</head>
        \\<body class="gallery-body">
        \\    <header class="md-top-app-bar">
        \\        <div class="md-top-app-bar__left">
        \\            <a href="/" class="md-header-logout-icon-btn" style="text-decoration: none;" title="Back to Gallery">
        \\                <svg viewBox="0 0 24 24" fill="currentColor"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"/></svg>
        \\            </a>
        \\        </div>
        \\        <span class="md-top-app-bar__title" style="display: flex; align-items: baseline; justify-content: center;">Admin <span style="font-size: 0.8rem; font-weight: 400; opacity: 0.7; margin-left: 8px;">v0.0.20</span></span>
        \\        <div class="md-top-app-bar__actions">
        \\            <form method="POST" action="/logout" style="margin: 0;">
        \\                <button type="submit" class="md-header-logout-icon-btn" title="Logout" aria-label="Logout">
        \\                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
        \\                        <path d="M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h8v-2H4V5z"/>
        \\                    </svg>
        \\                </button>
        \\            </form>
        \\        </div>
        \\    </header>
        \\
        \\    <main class="admin-container">
        \\        <section class="admin-section">
        \\            <div id="users-grid" class="users-grid">
        \\                <!-- Loaded dynamically -->
        \\            </div>
        \\        </section>
        \\
        \\        <!-- Floating Action Button -->
        \\        <button id="fab-add-user" class="md-fab" title="Add User">
        \\            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="32" height="32" fill="currentColor">
        \\                <path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/>
        \\            </svg>
        \\        </button>
        \\
        \\        <!-- Add User Modal -->
        \\        <div id="add-user-modal" class="modal-overlay">
        \\            <div class="modal-surface">
        \\                <h2>Add New User</h2>
        \\                <form id="add-user-form">
        \\                    <div class="form-group">
        \\                        <label>Username</label>
        \\                        <input type="text" id="new-username" required>
        \\                    </div>
        \\                    <div class="form-group">
        \\                        <label>Real Name</label>
        \\                        <input type="text" id="new-real-name">
        \\                    </div>
        \\                    <div class="form-group">
        \\                        <label>Password</label>
        \\                        <input type="password" id="new-password" required autocomplete="new-password">
        \\                    </div>
        \\                    <div class="form-group" style="display: flex; align-items: center; gap: 8px;">
        \\                        <input type="checkbox" id="new-is-admin" style="width: auto;">
        \\                        <label style="margin: 0;">Is Admin?</label>
        \\                    </div>
        \\                    <div class="modal-actions">
        \\                        <button type="button" id="btn-cancel-add" class="action-btn" style="color: var(--md-sys-color-on-surface-variant); margin-right: 16px;">Cancel</button>
        \\                        <button type="submit" class="btn-primary">Add User</button>
        \\                    </div>
        \\                </form>
        \\            </div>
        \\        </div>
        \\
        \\        <!-- Edit User Modal -->
        \\        <div id="edit-user-modal" class="modal-overlay">
        \\            <div class="modal-surface">
        \\                <h2>Edit User</h2>
        \\                <form id="edit-user-form">
        \\                    <input type="hidden" id="edit-username">
        \\                    <div class="form-group">
        \\                        <label>Real Name</label>
        \\                        <input type="text" id="edit-real-name">
        \\                    </div>
        \\                    <div class="form-group">
        \\                        <label>New Password (leave blank to keep current)</label>
        \\                        <input type="password" id="edit-password" autocomplete="new-password">
        \\                    </div>
        \\                    <div class="form-group" style="display: flex; align-items: center; gap: 8px;">
        \\                        <input type="checkbox" id="edit-is-admin" style="width: auto;">
        \\                        <label style="margin: 0;">Is Admin?</label>
        \\                    </div>
        \\                    <div class="modal-actions">
        \\                        <button type="button" id="btn-cancel-edit" class="action-btn" style="color: var(--md-sys-color-on-surface-variant); margin-right: 16px;">Cancel</button>
        \\                        <button type="submit" class="btn-primary">Save Changes</button>
        \\                    </div>
        \\                </form>
        \\            </div>
        \\        </div>
        \\    </main>
        \\
        \\    <div id="toast" class="toast">Saved successfully.</div>
        \\
        \\    <script src="/js/htmx.min.js" defer></script>
        \\    <script src="/js/alpine.min.js" defer></script>
        \\    <script src="/js/state.js" defer></script>
        \\    <script src="/js/alpine.min.js" defer></script>
        \\</body>
        \\</html>
        \\
    );
}

pub const albums_head_start =
    \\<!DOCTYPE html>
    \\<html lang="en">
    \\<head>
    \\    <meta charset="UTF-8">
    \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    \\    <title>Albums - Image Gallery</title>
    \\    <link rel="stylesheet" href="/css/styles.css">
    \\
;

pub const albums_body_top =
    \\</head>
    \\<body class="gallery-body" x-data="galleryState()" :class="{ 'selection-mode': selectedPhotos.length > 0 }">
    \\    <header class="md-top-app-bar" id="app-bar">
    \\        <div class="md-top-app-bar__left" id="app-bar-left">
    \\            <a href="/" class="md-header-logout-icon-btn" title="Gallery" style="text-decoration: none;">
    \\                <svg viewBox="0 0 24 24" fill="currentColor"><path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"/></svg>
    \\            </a>
    \\        </div>
    \\        <span class="md-top-app-bar__title" id="app-bar-title" style="display: flex; align-items: baseline;">Albums <span style="font-size: 0.8rem; font-weight: 400; opacity: 0.7; margin-left: 8px;">v0.0.20</span></span>
    \\        <div class="md-top-app-bar__actions" id="app-bar-actions">
    \\
;

pub const album_detail_head_start =
    \\<!DOCTYPE html>
    \\<html lang="en">
    \\<head>
    \\    <meta charset="UTF-8">
    \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    \\    <title>
;

pub const album_detail_head_end =
    \\ - Image Gallery</title>
    \\    <link rel="stylesheet" href="/css/styles.css">
    \\
;

pub const album_detail_body_top =
    \\</head>
    \\<body class="gallery-body" x-data="galleryState()" :class="{ 'selection-mode': selectedPhotos.length > 0 }">
    \\    <header class="md-top-app-bar" id="app-bar" :class="{ 'selection-mode': selectedPhotos.length > 0 }">
    \\        <div class="md-top-app-bar__left" id="app-bar-left">
    \\            <template x-if="selectedPhotos.length > 0">
    \\                <button class="md-selection-icon-btn" @click="clearSelection()" title="Clear selection" aria-label="Clear selection">
    \\                    <svg viewBox="0 0 24 24"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>
    \\                </button>
    \\            </template>
    \\            <template x-if="selectedPhotos.length === 0">
    \\                <a href="/albums" class="md-header-logout-icon-btn" title="Back to Albums" style="text-decoration: none;">
    \\                    <svg viewBox="0 0 24 24" fill="currentColor"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"/></svg>
    \\                </a>
    \\            </template>
    \\        </div>
    \\        <span class="md-top-app-bar__title" id="app-bar-title" style="display: flex; align-items: baseline;">
    \\            <template x-if="selectedPhotos.length > 0">
    \\                <span x-text="selectedPhotos.length + ' selected'"></span>
    \\            </template>
    \\            <template x-if="selectedPhotos.length === 0">
    \\                <span>
;

pub const album_detail_body_title_end =
    \\ <span style="font-size: 0.8rem; font-weight: 400; opacity: 0.7; margin-left: 8px;">v0.0.20</span></span>
    \\            </template>
    \\        </span>
    \\        <div class="md-top-app-bar__actions" id="app-bar-actions">
    \\
;

pub const album_detail_main_start =
    \\        </div>
    \\    </header>
    \\
    \\    <main class="gallery-container">
    \\        <div class="album-info-header" style="margin-bottom: 24px;">
    \\            <h1 style="margin: 0 0 8px 0; font-size: 2rem; font-weight: 600; color: var(--md-sys-color-on-surface);">
;

pub const album_detail_desc_start =
    \\</h1>
    \\            <p style="margin: 0; color: var(--md-sys-color-on-surface-variant); font-size: 1rem;">
;

pub const album_detail_desc_end =
    \\</p>
    \\        </div>
    \\        <div class="gallery" id="gallery-grid">
    \\
;

pub const album_detail_footer =
    \\    <script src="/js/htmx.min.js" defer></script>
    \\    <script src="/js/json-enc.js" defer></script>
    \\    <script src="/js/core.js" defer></script>
    \\    <script src="/js/state.js" defer></script>
    \\    <script src="/js/alpine.min.js" defer></script>
    \\</body>
    \\</html>
    \\
;

pub const albums_main_start =
    \\    <main class="gallery-container">
    \\        <div class="gallery" id="albums-grid" style="display: flex; flex-wrap: wrap; gap: 8px;">
    \\
;

pub const albums_footer =
    \\        </div>
    \\    </main>
    \\
    \\    <button class="md-fab" @click="modals.createAlbum = true" title="Create Album">
    \\        <svg viewBox="0 0 24 24" fill="currentColor" width="24" height="24"><path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/></svg>
    \\    </button>
    \\
    \\    <!-- Create Album Modal -->
    \\    <div id="create-album-modal" class="lightbox" :class="{ 'active': modals.createAlbum }" x-show="modals.createAlbum" x-transition x-cloak @click="modals.createAlbum = false">
    \\        <div class="modal-content" style="background: var(--md-sys-color-surface-container); padding: 24px; border-radius: 28px; width: 400px; max-width: 90%; box-shadow: 0 4px 12px rgba(0,0,0,0.15);" @click.stop>
    \\            <h2 style="margin-top: 0; color: var(--md-sys-color-on-surface); margin-bottom: 16px;">Create Album</h2>
    \\            <form hx-post="/api/albums" hx-ext="json-enc" @submit="modals.createAlbum = false; setTimeout(() => window.location.reload(), 200);">
    \\                <div style="margin-bottom: 16px;">
    \\                    <label style="display: block; font-weight: 500; margin-bottom: 4px;">Name</label>
    \\                    <input type="text" id="album-name" name="name" required style="width: 100%; border: 1px solid var(--md-sys-color-outline); border-radius: 8px; padding: 12px; box-sizing: border-box; background: transparent; color: inherit;">
    \\                </div>
    \\                <div style="margin-bottom: 24px;">
    \\                    <label style="display: block; font-weight: 500; margin-bottom: 4px;">Description (optional)</label>
    \\                    <textarea id="album-desc" name="description" rows="3" style="width: 100%; border: 1px solid var(--md-sys-color-outline); border-radius: 8px; padding: 12px; box-sizing: border-box; font-family: inherit; resize: vertical; background: transparent; color: inherit;"></textarea>
    \\                </div>
    \\                <div style="text-align: right;">
    \\                    <button type="button" class="md-menu-item" style="display: inline-block; width: auto; margin-right: 8px; background: transparent; border: none; cursor: pointer; color: var(--md-sys-color-on-surface);" @click="modals.createAlbum = false">Cancel</button>
    \\                    <button type="submit" style="background: var(--md-sys-color-primary); color: var(--md-sys-color-on-primary); border: none; padding: 10px 24px; border-radius: 20px; font-weight: 500; cursor: pointer;">Create</button>
    \\                </div>
    \\            </form>
    \\        </div>
    \\    </div>
    \\
    \\    <script src="/js/htmx.min.js" defer></script>
    \\    <script src="/js/json-enc.js" defer></script>
    \\    <script src="/js/core.js" defer></script>
    \\    <script src="/js/state.js" defer></script>
    \\    <script src="/js/alpine.min.js" defer></script>
    \\</body>
    \\</html>
    \\
;

pub const gallery_head_start = 
    \\<!DOCTYPE html>
    \\<html lang="en">
    \\<head>
    \\    <meta charset="UTF-8">
    \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    \\    <title>Image Gallery</title>
    \\    <link rel="stylesheet" href="/css/styles.css">
    \\
;

pub const gallery_body_top =
    \\</head>
    \\<body class="gallery-body" x-data="galleryState()" :class="{ 'selection-mode': selectedPhotos.length > 0 }">
    \\    <header class="md-top-app-bar" id="app-bar" :class="{ 'selection-mode': selectedPhotos.length > 0 }">
    \\        <div class="md-top-app-bar__left" id="app-bar-left">
    \\            <template x-if="selectedPhotos.length > 0">
    \\                <button class="md-selection-icon-btn" @click="clearSelection()" title="Clear selection" aria-label="Clear selection">
    \\                    <svg viewBox="0 0 24 24"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>
    \\                </button>
    \\            </template>
    \\            <template x-if="selectedPhotos.length === 0">
    \\                <a href="/albums" class="md-header-logout-icon-btn" title="Albums" style="text-decoration: none;">
    \\                    <svg viewBox="0 0 24 24" fill="currentColor"><path d="M22 16V4c0-1.1-.9-2-2-2H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2zm-11-4l2.03 2.71L16 11l4 5H8l3-4zM2 6v14c0 1.1.9 2 2 2h14v-2H4V6H2z"/></svg>
    \\                </a>
    \\            </template>
    \\        </div>
    \\        <span class="md-top-app-bar__title" id="app-bar-title" style="display: flex; align-items: baseline;" x-text="selectedPhotos.length > 0 ? selectedPhotos.length + ' selected' : 'Image Gallery'"></span>
    \\        <div class="md-top-app-bar__actions" id="app-bar-actions">
    \\
;

pub const gallery_header_end =
    \\        </div>
    \\    </header>
    \\
;

pub const gallery_main_start =
    \\    <main class="gallery-container">
    \\        <div class="gallery" id="gallery-grid">
    \\
;

pub const gallery_lightbox =
    \\        </div>
    \\    </main>
    \\    
    \\    <div id="lightbox" class="lightbox" :class="{ 'active': lightbox.isOpen }" x-show="lightbox.isOpen" x-transition x-cloak @click="closeLightbox()">
    \\        <div class="loader"></div>
    \\        <span class="close-btn">&times;</span>
    \\        <template x-if="!lightbox.isVideo">
    \\            <img id="lightbox-img" :src="lightbox.src" alt="Preview">
    \\        </template>
    \\        <template x-if="lightbox.isVideo">
    \\            <video id="lightbox-video" :src="lightbox.src" controls autoplay loop style="max-width: 100%; max-height: 100%;" @click.stop></video>
    \\        </template>
    \\    </div>
    \\
;

pub const gallery_footer =
    \\    <a href="/upload" class="md-fab" title="Upload Images">+</a>
    \\
    \\    <script src="/js/htmx.min.js" defer></script>
    \\    <script src="/js/json-enc.js" defer></script>
    \\    <script src="/js/core.js" defer></script>
    \\    <script src="/js/state.js" defer></script>
    \\    <script src="/js/alpine.min.js" defer></script>
    \\</body>
    \\</html>
    \\
;
