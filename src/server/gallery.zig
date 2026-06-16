const static = @import("gallery/static.zig");
const render = @import("gallery/render.zig");
const api = @import("gallery/api.zig");

// static.zig
pub const serveStaticFile = static.serveStaticFile;

// render.zig
pub const generateGalleryHtml = render.generateGalleryHtml;
pub const generateAlbumsHtml = render.generateAlbumsHtml;
pub const generateAlbumDetailHtml = render.generateAlbumDetailHtml;
pub const generateLoginHtml = render.generateLoginHtml;
pub const generateUploadHtml = render.generateUploadHtml;
pub const generateUsersHtml = render.generateUsersHtml;

// api.zig
pub const handleCreateAlbum = api.handleCreateAlbum;
pub const handleListAlbums = api.handleListAlbums;
pub const handleAddPhotosToAlbum = api.handleAddPhotosToAlbum;
pub const handleRemovePhotoFromAlbum = api.handleRemovePhotoFromAlbum;
