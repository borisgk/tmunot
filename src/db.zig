const core = @import("db/core.zig");
const photos = @import("db/photos.zig");
const albums = @import("db/albums.zig");
const users = @import("db/users.zig");
pub const write_queue = @import("db/write_queue.zig");

// From core
pub const init = core.init;
pub const deinit = core.deinit;
pub const sqlite3 = core.sqlite3;

// From photos
pub const PhotoRecord = photos.PhotoRecord;
pub const PhotoExifRecord = photos.PhotoExifRecord;
pub const VideoMetadataRecord = photos.VideoMetadataRecord;
pub const LocationRecord = photos.LocationRecord;
pub const insertPhoto = photos.insertPhoto;
pub const updatePhotoDimensions = photos.updatePhotoDimensions;
pub const getPhotoLocation = photos.getPhotoLocation;
pub const getPhotoLocationForUser = photos.getPhotoLocationForUser;
pub const getUserPhotos = photos.getUserPhotos;
pub const getUserPhotoYears = photos.getUserPhotoYears;
pub const getUserPhotosFiltered = photos.getUserPhotosFiltered;
pub const insertPhotoExif = photos.insertPhotoExif;
pub const getPhotoExif = photos.getPhotoExif;
pub const insertVideoMetadata = photos.insertVideoMetadata;
pub const getVideoMetadata = photos.getVideoMetadata;
pub const deletePhoto = photos.deletePhoto;
pub const updatePhotoDate = photos.updatePhotoDate;
pub const getPhotoDate = photos.getPhotoDate;

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

// From users
pub const UserRecord = users.UserRecord;
pub const initUsersDb = users.initUsersDb;
pub const deinitUsersDb = users.deinitUsersDb;
pub const insertUser = users.insertUser;
pub const updateUser = users.updateUser;
pub const deleteUser = users.deleteUser;
pub const getUser = users.getUser;
pub const getUsers = users.getUsers;

// DB write queue (worker OS threads must use these instead of direct DB calls)
pub const pushDbInsertPhoto         = write_queue.pushInsertPhoto;
pub const pushDbInsertPhotoExif     = write_queue.pushInsertPhotoExif;
pub const pushDbInsertVideoMetadata = write_queue.pushInsertVideoMetadata;
