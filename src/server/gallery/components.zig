const std = @import("std");
const db = @import("../../db.zig");

pub const shared_modals_html = 
    \\    <!-- Global Overflow Menu -->
    \\    <div id="global-menu" class="md-menu">
    \\        <button class="md-menu-item" id="menu-metadata">
    \\            <svg viewBox="0 0 24 24"><path fill="currentColor" d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/></svg>
    \\            <span>View metadata</span>
    \\        </button>
    \\        <button class="md-menu-item" id="menu-change-date">
    \\            <svg viewBox="0 0 24 24"><path fill="currentColor" d="M19 3h-1V1h-2v2H8V1H6v2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16H5V8h14v11zM7 10h5v5H7v-5z"/></svg>
    \\            <span>Change Date/Time</span>
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
    \\                <button id="metadata-refresh-btn" class="md-menu-item" style="display: inline-block; width: auto; background: var(--md-sys-color-secondary); color: var(--md-sys-color-on-secondary); border: none; padding: 10px 24px; border-radius: 20px; font-weight: 500; cursor: pointer; margin-right: 8px;" onclick="refreshMetadata()">Refresh</button>
    \\                <button class="md-menu-item" style="display: inline-block; width: auto; background: var(--md-sys-color-primary); color: var(--md-sys-color-on-primary); border: none; padding: 10px 24px; border-radius: 20px; font-weight: 500; cursor: pointer;" onclick="closeMetadataModal({target:{id:'metadata-modal'}})">Close</button>
    \\            </div>
    \\        </div>
    \\    </div>
    \\
    \\    <!-- Album Selection Modal -->
    \\    <div id="album-select-modal" class="lightbox" onclick="closeAlbumSelectModal(event)">
    \\        <div class="modal-content" style="background: var(--md-sys-color-surface-container); padding: 24px; border-radius: 28px; width: 400px; max-width: 90%; box-shadow: 0 4px 12px rgba(0,0,0,0.15);" onclick="event.stopPropagation()">
    \\            <h3 style="margin-top: 0; color: var(--md-sys-color-on-surface); margin-bottom: 16px;">Add to Album</h3>
    \\            <div id="album-select-list" style="overflow-y: auto; max-height: 300px; margin-bottom: 24px; display: flex; flex-direction: column; gap: 8px;">
    \\                <!-- Album options loaded dynamically -->
    \\            </div>
    \\            <div style="text-align: right;">
    \\                <button class="md-menu-item" style="display: inline-block; width: auto; background: transparent; color: var(--md-sys-color-primary); border: none; padding: 10px 16px; border-radius: 20px; font-weight: 500; cursor: pointer;" onclick="closeAlbumSelectModal({target:{id:'album-select-modal'}})">Cancel</button>
    \\            </div>
    \\        </div>
    \\    </div>
    \\
    \\    <!-- Change Date Modal -->
    \\    <div id="change-date-modal" class="lightbox" onclick="closeChangeDateModal(event)">
    \\        <div class="modal-content" style="background: var(--md-sys-color-surface-container); padding: 24px; border-radius: 28px; width: 350px; max-width: 90%; box-shadow: 0 4px 12px rgba(0,0,0,0.15);" onclick="event.stopPropagation()">
    \\            <h3 style="margin-top: 0; color: var(--md-sys-color-on-surface); margin-bottom: 16px;">Change Date/Time</h3>
    \\            <input type="datetime-local" step="1" id="change-date-input" style="width: 100%; padding: 12px; border-radius: 12px; border: 1px solid var(--md-sys-color-outline); background: var(--md-sys-color-surface); color: var(--md-sys-color-on-surface); font-family: inherit; font-size: 16px; margin-bottom: 24px; box-sizing: border-box;" />
    \\            <div style="text-align: right;">
    \\                <button class="md-menu-item" style="display: inline-block; width: auto; background: transparent; color: var(--md-sys-color-primary); border: none; padding: 10px 16px; border-radius: 20px; font-weight: 500; cursor: pointer; margin-right: 8px;" onclick="closeChangeDateModal({target:{id:'change-date-modal'}})">Cancel</button>
    \\                <button class="md-menu-item" style="display: inline-block; width: auto; background: var(--md-sys-color-primary); color: var(--md-sys-color-on-primary); border: none; padding: 10px 24px; border-radius: 20px; font-weight: 500; cursor: pointer;" onclick="submitChangeDate()">Save</button>
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

pub fn getDisplayYearMonth(r: db.PhotoRecord) struct { year: []const u8, month: []const u8 } {
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

pub fn renderMediaCard(alloc: std.mem.Allocator, r: db.PhotoRecord, idx: usize) ![]const u8 {
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

    const shooting_date_str = r.shooting_date orelse "";
    if (is_video) {
        return try std.fmt.allocPrint(alloc,
            \\        <div class="card video-card" data-uuid="{s}" data-year="{s}" data-month="{s}" data-date="{s}" style="flex:{d:.4} 1 calc({d:.4} * var(--target-h));" onclick="openLightbox('/previews/{s}.{s}')">
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
        , .{ r.uuid, ym.year, ym.month, shooting_date_str, ratio, ratio, r.uuid, r.extension, r.uuid, r.extension, r.uuid, r.extension, r.filename, loading_attr, priority_attr, r.filename });
    } else {
        return try std.fmt.allocPrint(alloc,
            \\        <div class="card" data-uuid="{s}" data-year="{s}" data-month="{s}" data-date="{s}" style="flex:{d:.4} 1 calc({d:.4} * var(--target-h));" onclick="openLightbox('/previews/{s}.{s}')">
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
        , .{ r.uuid, ym.year, ym.month, shooting_date_str, ratio, ratio, r.uuid, r.extension, r.uuid, r.extension, r.uuid, r.extension, r.filename, loading_attr, priority_attr, r.filename });
    }
}

pub fn replacePlaceholder(alloc: std.mem.Allocator, input: []const u8, target: []const u8, replacement: []const u8) ![]const u8 {
    const size = std.mem.replacementSize(u8, input, target, replacement);
    const output = try alloc.alloc(u8, size);
    _ = std.mem.replace(u8, input, target, replacement, output);
    return output;
}
