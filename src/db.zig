const core = @import("db/core.zig");
const photos = @import("db/photos.zig");
const albums = @import("db/albums.zig");

// From core
pub const init = core.init;
pub const deinit = core.deinit;
pub const sqlite3 = core.sqlite3;

// From photos
pub const PhotoRecord = photos.PhotoRecord;
pub const PhotoExifRecord = photos.PhotoExifRecord;
pub const LocationRecord = photos.LocationRecord;
pub const insertPhoto = photos.insertPhoto;
pub const updatePhotoDimensions = photos.updatePhotoDimensions;
pub const getPhotoLocation = photos.getPhotoLocation;
pub const getUserPhotos = photos.getUserPhotos;
pub const insertPhotoExif = photos.insertPhotoExif;
pub const deletePhoto = photos.deletePhoto;

// From albums
pub const AlbumRecord = albums.AlbumRecord;
pub const AlbumPhotoRecord = albums.AlbumPhotoRecord;
pub const insertAlbum = albums.insertAlbum;
pub const updateAlbumCover = albums.updateAlbumCover;
pub const insertAlbumPhoto = albums.insertAlbumPhoto;
pub const getAlbums = albums.getAlbums;
pub const getAlbum = albums.getAlbum;
pub const getAlbumPhotos = albums.getAlbumPhotos;
pub const deleteAlbum = albums.deleteAlbum;
pub const deleteAlbumPhoto = albums.deleteAlbumPhoto;
