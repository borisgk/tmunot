const std = @import("std");
const db = @import("../../db.zig");
const components = @import("components.zig");

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

    try writer.writeAll(
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\    <meta charset="UTF-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\    <title>Image Gallery</title>
        \\    <link rel="stylesheet" href="/css/styles.css">
        \\
    );

    // 1. Dynamic style tag
    try components.renderDynamicStyle(writer, thumbnail_height);

    // 2. Dynamic LCP Preload in HTML Head: If there are photos, preload the first thumbnail immediately
    if (photos.len > 0) {
        const first_photo = photos[0];
        try components.renderPreloadTag(writer, first_photo.uuid, first_photo.extension);
    }

    try writer.writeAll(
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
    );

    // Get user to see if admin & avatar
    const user_opt = try db.getUser(username, alloc);
    const is_admin = if (user_opt) |u| u.is_admin else false;
    const avatar_ext = if (user_opt) |u| u.avatar_ext else null;

    // Render logout/topbar actions
    try components.renderLogout(writer, is_admin, username, avatar_ext);

    // Render selection actions
    try components.renderSelectionActions(writer);

    try writer.writeAll(
        \\        </div>
        \\    </header>
        \\
    );

    // Collect unique years for dynamic filtering dropdown
    var years_list = std.ArrayList([]const u8).empty;
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

    try components.renderFilterSelect(writer, years_list.items);

    try writer.writeAll(
        \\    <main class="gallery-container">
        \\        <div class="gallery" id="gallery-grid">
        \\
    );

    // Render photos
    for (photos, 0..) |r, idx| {
        try components.renderMediaCard(writer, r, idx);
    }

    // Dynamic spacer to prevent the last row from stretching
    try components.renderGallerySpacer(writer);

    try writer.writeAll(
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
    );

    // Render shared modals
    try components.renderSharedModals(writer);

    try writer.writeAll(
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
    );

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

    try writer.writeAll(
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\    <meta charset="UTF-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\    <title>Albums - Image Gallery</title>
        \\    <link rel="stylesheet" href="/css/styles.css">
        \\
    );

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

    try writer.writeAll(
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
    );

    const user_opt = try db.getUser(username, alloc);
    const is_admin = if (user_opt) |u| u.is_admin else false;
    const avatar_ext = if (user_opt) |u| u.avatar_ext else null;

    try components.renderLogout(writer, is_admin, username, avatar_ext);

    try writer.writeAll(
        \\        </div>
        \\    </header>
        \\
        \\    <main class="gallery-container">
        \\        <div class="gallery" id="albums-grid" style="display: flex; flex-wrap: wrap; gap: 8px;">
        \\
    );

    if (albums.len == 0) {
        try components.renderAlbumEmpty(writer);
    } else {
        for (albums, 0..) |a, idx| {
            try components.renderAlbumCard(writer, a.uuid, a.name, a.photo_count, a.description, a.cover_photo_uuid, a.cover_photo_extension, idx);
        }
    }

    try writer.writeAll(
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
    );

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

    try writer.writeAll(
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\    <meta charset="UTF-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\    <title>
    );

    try components.writeEscapedHtml(writer, album.name);

    try writer.writeAll(
        \\ - Image Gallery</title>
        \\    <link rel="stylesheet" href="/css/styles.css">
        \\
    );

    // 1. Dynamic style tag
    try components.renderDynamicStyle(writer, thumbnail_height);

    // 2. LCP Preload tag
    if (photos.len > 0) {
        const first_photo = photos[0];
        try components.renderPreloadTag(writer, first_photo.uuid, first_photo.extension);
    }

    try writer.writeAll(
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
    );

    try components.writeEscapedHtml(writer, album.name);

    try writer.writeAll(
        \\ <span style="font-size: 0.8rem; font-weight: 400; opacity: 0.7; margin-left: 8px;">v0.0.20</span></span>
        \\            </template>
        \\        </span>
        \\        <div class="md-top-app-bar__actions" id="app-bar-actions">
        \\
    );

    const user_opt = try db.getUser(username, alloc);
    const is_admin = if (user_opt) |u| u.is_admin else false;
    const avatar_ext = if (user_opt) |u| u.avatar_ext else null;

    try components.renderLogout(writer, is_admin, username, avatar_ext);
    try components.renderSelectionActions(writer);

    try writer.writeAll(
        \\        </div>
        \\    </header>
        \\
        \\    <main class="gallery-container">
        \\        <div class="album-info-header" style="margin-bottom: 24px;">
        \\            <h1 style="margin: 0 0 8px 0; font-size: 2rem; font-weight: 600; color: var(--md-sys-color-on-surface);">
    );

    try components.writeEscapedHtml(writer, album.name);

    try writer.writeAll(
        \\</h1>
        \\            <p style="margin: 0; color: var(--md-sys-color-on-surface-variant); font-size: 1rem;">
    );

    if (album.description) |desc| {
        try components.writeEscapedHtml(writer, desc);
    }

    try writer.writeAll(
        \\</p>
        \\        </div>
        \\        <div class="gallery" id="gallery-grid">
        \\
    );

    if (photos.len == 0) {
        try components.renderAlbumPhotosEmpty(writer);
    } else {
        for (photos, 0..) |r, idx| {
            try components.renderMediaCard(writer, r, idx);
        }
        try components.renderGallerySpacer(writer);
    }

    try writer.writeAll(
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
    );

    try components.renderSharedModals(writer);

    try writer.writeAll(
        \\    <script src="/js/htmx.min.js" defer></script>
        \\    <script src="/js/json-enc.js" defer></script>
        \\    <script src="/js/core.js" defer></script>
        \\    <script src="/js/state.js" defer></script>
        \\    <script src="/js/alpine.min.js" defer></script>
        \\</body>
        \\</html>
        \\
    );

    return try aw.toOwnedSlice();
}

pub fn generateLoginHtml(allocator: std.mem.Allocator, csrf_token: []const u8, error_message: []const u8) ![]u8 {
    _ = allocator;
    var aw = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    errdefer aw.deinit();
    const writer = &aw.writer;

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

    try components.writeEscapedHtml(writer, error_message);

    try writer.writeAll(
        \\</div>
        \\        </form>
        \\    </div>
        \\</body>
        \\</html>
        \\
    );

    return try aw.toOwnedSlice();
}

pub fn generateUploadHtml(allocator: std.mem.Allocator) ![]u8 {
    _ = allocator;
    var aw = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    errdefer aw.deinit();
    const writer = &aw.writer;

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
        \\    <div class="upload-container">
        \\        <h2 style="display: flex; align-items: baseline; justify-content: center;">Upload Media <span style="font-size: 0.8rem; font-weight: 400; opacity: 0.7; margin-left: 8px;">v0.0.20</span></h2>
        \\        <p class="subtitle">Select or drag and drop your files to upload them to the gallery</p>
        \\
        \\        <div id="dropzone" class="dropzone">
        \\            <svg viewBox="0 0 24 24">
        \\                <path
        \\                    d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM14 13v4h-4v-4H7l5-5 5 5h-3z" />
        \\            </svg>
        \\            <p>Drag and drop media files here</p>
        \\            <span>or click to browse from files</span>
        \\            <input type="file" id="file-input" multiple accept="image/*,video/*" style="display: none;">
        \\        </div>
        \\
        \\        <h3 id="staged-title" class="staged-title">Staged Files</h3>
        \\        <div id="staged-list" class="staged-list">
        \\            <!-- Dynamic staged queue item list -->
        \\        </div>
        \\
        \\
        \\
        \\        <div class="error-message" id="error-message" style="margin-bottom: 1.5rem; text-align: center;"></div>
        \\
        \\        <div class="upload-actions">
        \\            <a href="/" class="secondary-btn">Cancel</a>
        \\            <button id="upload-btn" class="primary-btn" disabled>Upload</button>
        \\        </div>
        \\    </div>
        \\
        \\    <script src="/js/htmx.min.js" defer></script>
        \\    <script src="/js/alpine.min.js" defer></script>
        \\    <script src="/js/core.js" defer></script>
        \\    <script src="/js/upload.js" defer></script>
        \\</body>
        \\
        \\</html>
        \\
    );

    return try aw.toOwnedSlice();
}

pub fn generateUsersHtml(allocator: std.mem.Allocator) ![]u8 {
    _ = allocator;
    var aw = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    errdefer aw.deinit();
    const writer = &aw.writer;

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
        \\    <script src="/js/core.js" defer></script>
        \\    <script src="/js/users.js" defer></script>
        \\</body>
        \\</html>
        \\
    );

    return try aw.toOwnedSlice();
}
