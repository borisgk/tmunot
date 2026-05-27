const std = @import("std");

pub const sqlite3 = opaque {};
pub const sqlite3_stmt = opaque {};

pub const SQLITE_OK: c_int = 0;
pub const SQLITE_ROW: c_int = 100;
pub const SQLITE_DONE: c_int = 101;
pub const SQLITE_NULL: c_int = 5;

pub const SQLITE_OPEN_READONLY: c_int = 0x00000001;
pub const SQLITE_OPEN_READWRITE: c_int = 0x00000002;
pub const SQLITE_OPEN_CREATE: c_int = 0x00000004;
pub const SQLITE_OPEN_FULLMUTEX: c_int = 0x00010000;

pub const SQLITE_TRANSIENT = @as(?*anyopaque, @ptrFromInt(@as(usize, @bitCast(@as(isize, -1)))));

pub extern "c" fn sqlite3_open_v2(
    filename: [*c]const u8,
    ppDb: *?*sqlite3,
    flags: c_int,
    zVfs: [*c]const u8,
) c_int;

pub extern "c" fn sqlite3_close(db: ?*sqlite3) c_int;

pub extern "c" fn sqlite3_exec(
    db: ?*sqlite3,
    sql: [*c]const u8,
    callback: ?*const fn (?*anyopaque, c_int, [*c][*c]u8, [*c][*c]u8) callconv(.c) c_int,
    arg: ?*anyopaque,
    errmsg: *[*c]u8,
) c_int;

pub extern "c" fn sqlite3_free(ptr: ?*anyopaque) void;

pub extern "c" fn sqlite3_prepare_v2(
    db: ?*sqlite3,
    zSql: [*c]const u8,
    nByte: c_int,
    ppStmt: *?*sqlite3_stmt,
    pzTail: ?*[*c]const u8,
) c_int;

pub extern "c" fn sqlite3_finalize(pStmt: ?*sqlite3_stmt) c_int;

pub extern "c" fn sqlite3_step(pStmt: ?*sqlite3_stmt) c_int;

pub extern "c" fn sqlite3_errmsg(db: ?*sqlite3) [*c]const u8;

pub extern "c" fn sqlite3_bind_text(
    pStmt: ?*sqlite3_stmt,
    idx: c_int,
    value: [*c]const u8,
    nBytes: c_int,
    destructor: ?*anyopaque,
) c_int;

pub extern "c" fn sqlite3_bind_null(pStmt: ?*sqlite3_stmt, idx: c_int) c_int;

pub extern "c" fn sqlite3_bind_int(pStmt: ?*sqlite3_stmt, idx: c_int, value: c_int) c_int;

pub extern "c" fn sqlite3_column_text(pStmt: ?*sqlite3_stmt, iCol: c_int) [*c]const u8;

pub extern "c" fn sqlite3_column_bytes(pStmt: ?*sqlite3_stmt, iCol: c_int) c_int;

pub extern "c" fn sqlite3_column_int(pStmt: ?*sqlite3_stmt, iCol: c_int) c_int;

pub extern "c" fn sqlite3_column_type(pStmt: ?*sqlite3_stmt, iCol: c_int) c_int;

pub const PhotoRecord = struct {
    uuid: []const u8,
    username: []const u8,
    filename: []const u8,
    extension: []const u8,
    year: []const u8,
    month: []const u8,
    day: []const u8,
    shooting_date: ?[]const u8,
    upload_date: []const u8,
    width: ?i32,
    height: ?i32,
};

pub const PhotoExifRecord = struct {
    uuid: []const u8,
    GPSVersionID: ?[]const u8 = null,
    InteroperabilityIndex: ?[]const u8 = null,
    InteroperabilityVersion: ?[]const u8 = null,
    GPSLongitudeRef: ?[]const u8 = null,
    GPSLongitude: ?[]const u8 = null,
    GPSAltitudeRef: ?[]const u8 = null,
    GPSAltitude: ?[]const u8 = null,
    GPSTimeStamp: ?[]const u8 = null,
    GPSSatellites: ?[]const u8 = null,
    GPSStatus: ?[]const u8 = null,
    GPSMeasureMode: ?[]const u8 = null,
    GPSDOP: ?[]const u8 = null,
    GPSSpeedRef: ?[]const u8 = null,
    GPSSpeed: ?[]const u8 = null,
    GPSTrackRef: ?[]const u8 = null,
    GPSTrack: ?[]const u8 = null,
    GPSImgDirectionRef: ?[]const u8 = null,
    GPSImgDirection: ?[]const u8 = null,
    GPSMapDatum: ?[]const u8 = null,
    GPSDestLatitudeRef: ?[]const u8 = null,
    GPSDestLatitude: ?[]const u8 = null,
    GPSDestLongitudeRef: ?[]const u8 = null,
    GPSDestLongitude: ?[]const u8 = null,
    GPSDestBearingRef: ?[]const u8 = null,
    GPSDestBearing: ?[]const u8 = null,
    GPSDestDistanceRef: ?[]const u8 = null,
    GPSDestDistance: ?[]const u8 = null,
    GPSProcessingMethod: ?[]const u8 = null,
    GPSAreaInformation: ?[]const u8 = null,
    GPSDateStamp: ?[]const u8 = null,
    GPSDifferential: ?[]const u8 = null,
    GPSHPositioningError: ?[]const u8 = null,
    NewSubfileType: ?[]const u8 = null,
    ImageWidth: ?[]const u8 = null,
    ImageLength: ?[]const u8 = null,
    BitsPerSample: ?[]const u8 = null,
    Compression: ?[]const u8 = null,
    PhotometricInterpretation: ?[]const u8 = null,
    FillOrder: ?[]const u8 = null,
    DocumentName: ?[]const u8 = null,
    ImageDescription: ?[]const u8 = null,
    Make: ?[]const u8 = null,
    Model: ?[]const u8 = null,
    StripOffsets: ?[]const u8 = null,
    Orientation: ?[]const u8 = null,
    SamplesPerPixel: ?[]const u8 = null,
    RowsPerStrip: ?[]const u8 = null,
    StripByteCounts: ?[]const u8 = null,
    XResolution: ?[]const u8 = null,
    YResolution: ?[]const u8 = null,
    PlanarConfiguration: ?[]const u8 = null,
    ResolutionUnit: ?[]const u8 = null,
    TransferFunction: ?[]const u8 = null,
    Software: ?[]const u8 = null,
    DateTime: ?[]const u8 = null,
    Artist: ?[]const u8 = null,
    WhitePoint: ?[]const u8 = null,
    PrimaryChromaticities: ?[]const u8 = null,
    SubIFDs: ?[]const u8 = null,
    TransferRange: ?[]const u8 = null,
    JPEGProc: ?[]const u8 = null,
    JPEGInterchangeFormat: ?[]const u8 = null,
    JPEGInterchangeFormatLength: ?[]const u8 = null,
    YCbCrCoefficients: ?[]const u8 = null,
    YCbCrSubSampling: ?[]const u8 = null,
    YCbCrPositioning: ?[]const u8 = null,
    ReferenceBlackWhite: ?[]const u8 = null,
    XMLPacket: ?[]const u8 = null,
    RelatedImageFileFormat: ?[]const u8 = null,
    RelatedImageWidth: ?[]const u8 = null,
    RelatedImageLength: ?[]const u8 = null,
    CFARepeatPatternDim: ?[]const u8 = null,
    CFAPattern: ?[]const u8 = null,
    BatteryLevel: ?[]const u8 = null,
    Copyright: ?[]const u8 = null,
    ExposureTime: ?[]const u8 = null,
    FNumber: ?[]const u8 = null,
    IPTCNAA: ?[]const u8 = null,
    ImageResources: ?[]const u8 = null,
    InterColorProfile: ?[]const u8 = null,
    ExposureProgram: ?[]const u8 = null,
    SpectralSensitivity: ?[]const u8 = null,
    ISOSpeedRatings: ?[]const u8 = null,
    OECF: ?[]const u8 = null,
    TimeZoneOffset: ?[]const u8 = null,
    SensitivityType: ?[]const u8 = null,
    StandardOutputSensitivity: ?[]const u8 = null,
    RecommendedExposureIndex: ?[]const u8 = null,
    @"ISO Speed": ?[]const u8 = null,
    @"ISO Speed Latitude yyy": ?[]const u8 = null,
    @"ISO Speed Latitude zzz": ?[]const u8 = null,
    ExifVersion: ?[]const u8 = null,
    DateTimeOriginal: ?[]const u8 = null,
    DateTimeDigitized: ?[]const u8 = null,
    OffsetTime: ?[]const u8 = null,
    OffsetTimeOriginal: ?[]const u8 = null,
    OffsetTimeDigitized: ?[]const u8 = null,
    ComponentsConfiguration: ?[]const u8 = null,
    CompressedBitsPerPixel: ?[]const u8 = null,
    ShutterSpeedValue: ?[]const u8 = null,
    ApertureValue: ?[]const u8 = null,
    BrightnessValue: ?[]const u8 = null,
    ExposureBiasValue: ?[]const u8 = null,
    MaxApertureValue: ?[]const u8 = null,
    SubjectDistance: ?[]const u8 = null,
    MeteringMode: ?[]const u8 = null,
    LightSource: ?[]const u8 = null,
    Flash: ?[]const u8 = null,
    FocalLength: ?[]const u8 = null,
    SubjectArea: ?[]const u8 = null,
    TIFFEPStandardID: ?[]const u8 = null,
    MakerNote: ?[]const u8 = null,
    UserComment: ?[]const u8 = null,
    SubsecTime: ?[]const u8 = null,
    SubSecTimeOriginal: ?[]const u8 = null,
    SubSecTimeDigitized: ?[]const u8 = null,
    XPTitle: ?[]const u8 = null,
    XPComment: ?[]const u8 = null,
    XPAuthor: ?[]const u8 = null,
    XPKeywords: ?[]const u8 = null,
    XPSubject: ?[]const u8 = null,
    FlashpixVersion: ?[]const u8 = null,
    ColorSpace: ?[]const u8 = null,
    PixelXDimension: ?[]const u8 = null,
    PixelYDimension: ?[]const u8 = null,
    RelatedSoundFile: ?[]const u8 = null,
    FlashEnergy: ?[]const u8 = null,
    SpatialFrequencyResponse: ?[]const u8 = null,
    FocalPlaneXResolution: ?[]const u8 = null,
    FocalPlaneYResolution: ?[]const u8 = null,
    FocalPlaneResolutionUnit: ?[]const u8 = null,
    SubjectLocation: ?[]const u8 = null,
    ExposureIndex: ?[]const u8 = null,
    SensingMethod: ?[]const u8 = null,
    FileSource: ?[]const u8 = null,
    SceneType: ?[]const u8 = null,
    CustomRendered: ?[]const u8 = null,
    ExposureMode: ?[]const u8 = null,
    WhiteBalance: ?[]const u8 = null,
    DigitalZoomRatio: ?[]const u8 = null,
    FocalLengthIn35mmFilm: ?[]const u8 = null,
    SceneCaptureType: ?[]const u8 = null,
    GainControl: ?[]const u8 = null,
    Contrast: ?[]const u8 = null,
    Saturation: ?[]const u8 = null,
    Sharpness: ?[]const u8 = null,
    DeviceSettingDescription: ?[]const u8 = null,
    SubjectDistanceRange: ?[]const u8 = null,
    ImageUniqueID: ?[]const u8 = null,
    CameraOwnerName: ?[]const u8 = null,
    BodySerialNumber: ?[]const u8 = null,
    LensSpecification: ?[]const u8 = null,
    LensMake: ?[]const u8 = null,
    LensModel: ?[]const u8 = null,
    LensSerialNumber: ?[]const u8 = null,
    CompositeImage: ?[]const u8 = null,
    SourceImageNumberOfCompositeImage: ?[]const u8 = null,
    SourceExposureTimesOfCompositeImage: ?[]const u8 = null,
    Gamma: ?[]const u8 = null,
    PrintImageMatching: ?[]const u8 = null,
    Padding: ?[]const u8 = null,
};


pub const LocationRecord = struct {
    username: []const u8,
    year: []const u8,
    month: []const u8,
    extension: []const u8,
};

var db_mutex = std.Io.Mutex.init;
var db_conn: ?*sqlite3 = null;
var global_io: ?std.Io = null;

pub fn init(allocator: std.mem.Allocator, io: std.Io, db_path: []const u8) !void {
    db_mutex.lockUncancelable(io);
    defer db_mutex.unlock(io);

    if (db_conn != null) return;
    global_io = io;

    const db_path_c = try std.fmt.allocPrintSentinel(allocator, "{s}", .{db_path}, 0);
    defer allocator.free(db_path_c);

    var temp_db: ?*sqlite3 = null;
    const rc = sqlite3_open_v2(
        db_path_c,
        &temp_db,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
        null,
    );

    if (rc != SQLITE_OK) {
        if (temp_db) |t| _ = sqlite3_close(t);
        return error.SqliteOpenFailed;
    }
    db_conn = temp_db;

    // Set WAL mode - REQUIRED by the user "always be using sqlite WAL"
    var err_msg: [*c]u8 = null;
    const wal_rc = sqlite3_exec(db_conn, "PRAGMA journal_mode=WAL;", null, null, &err_msg);
    if (wal_rc != SQLITE_OK) {
        std.debug.print("Failed to set WAL mode: {s}\n", .{err_msg});
        if (err_msg) |msg| sqlite3_free(msg);
        return error.SqliteExecFailed;
    }
    if (err_msg) |msg| sqlite3_free(msg);
    std.debug.print("SQLite WAL mode initialized successfully.\n", .{});

    // Create table and indices
    const create_sql =
        \\CREATE TABLE IF NOT EXISTS photos (
        \\    uuid TEXT PRIMARY KEY,
        \\    username TEXT NOT NULL,
        \\    filename TEXT NOT NULL,
        \\    extension TEXT NOT NULL,
        \\    year TEXT NOT NULL,
        \\    month TEXT NOT NULL,
        \\    day TEXT NOT NULL,
        \\    shooting_date TEXT,
        \\    upload_date TEXT NOT NULL,
        \\    width INTEGER,
        \\    height INTEGER
        \\);
        \\CREATE INDEX IF NOT EXISTS idx_photos_username ON photos(username);
        \\CREATE INDEX IF NOT EXISTS idx_photos_shooting_upload ON photos(shooting_date, upload_date);
    ;

    const create_exif_sql = comptime blk: {
        @setEvalBranchQuota(10000);
        var sql: []const u8 = "CREATE TABLE IF NOT EXISTS photo_exif (uuid TEXT PRIMARY KEY REFERENCES photos(uuid) ON DELETE CASCADE";
        for (std.meta.fields(PhotoExifRecord)) |field| {
            if (std.mem.eql(u8, field.name, "uuid")) continue;
            sql = sql ++ ", \"" ++ field.name ++ "\" TEXT";
        }
        sql = sql ++ ");\nCREATE INDEX IF NOT EXISTS idx_photo_exif_make ON photo_exif(\"Make\");\nCREATE INDEX IF NOT EXISTS idx_photo_exif_model ON photo_exif(\"Model\");\x00";
        break :blk sql;
    };

    const create_rc = sqlite3_exec(db_conn, create_sql, null, null, &err_msg);
    if (create_rc != SQLITE_OK) {
        std.debug.print("Failed to run migrations: {s}\n", .{err_msg});
        if (err_msg) |msg| sqlite3_free(msg);
        return error.SqliteExecFailed;
    }
    if (err_msg) |msg| sqlite3_free(msg);

    const create_exif_rc = sqlite3_exec(db_conn, create_exif_sql.ptr, null, null, &err_msg);
    if (create_exif_rc != SQLITE_OK) {
        std.debug.print("Failed to run exif migrations: {s}\n", .{err_msg});
        if (err_msg) |msg| sqlite3_free(msg);
        return error.SqliteExecFailed;
    }
    if (err_msg) |msg| sqlite3_free(msg);
}

pub fn deinit() void {
    if (global_io) |io| {
        db_mutex.lockUncancelable(io);
        defer db_mutex.unlock(io);

        if (db_conn) |db| {
            _ = sqlite3_close(db);
            db_conn = null;
        }
    }
}

pub fn insertPhoto(record: PhotoRecord) !void {
    const io = global_io orelse return error.DbNotInitialized;
    db_mutex.lockUncancelable(io);
    defer db_mutex.unlock(io);

    const db = db_conn orelse return error.DbNotInitialized;

    const insert_sql =
        \\INSERT INTO photos (uuid, username, filename, extension, year, month, day, shooting_date, upload_date, width, height)
        \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ;

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, insert_sql, -1, &stmt, null) != SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = sqlite3_finalize(stmt);

    // Bind parameters
    _ = sqlite3_bind_text(stmt, 1, record.uuid.ptr, @intCast(record.uuid.len), SQLITE_TRANSIENT);
    _ = sqlite3_bind_text(stmt, 2, record.username.ptr, @intCast(record.username.len), SQLITE_TRANSIENT);
    _ = sqlite3_bind_text(stmt, 3, record.filename.ptr, @intCast(record.filename.len), SQLITE_TRANSIENT);
    _ = sqlite3_bind_text(stmt, 4, record.extension.ptr, @intCast(record.extension.len), SQLITE_TRANSIENT);
    _ = sqlite3_bind_text(stmt, 5, record.year.ptr, @intCast(record.year.len), SQLITE_TRANSIENT);
    _ = sqlite3_bind_text(stmt, 6, record.month.ptr, @intCast(record.month.len), SQLITE_TRANSIENT);
    _ = sqlite3_bind_text(stmt, 7, record.day.ptr, @intCast(record.day.len), SQLITE_TRANSIENT);

    if (record.shooting_date) |sd| {
        _ = sqlite3_bind_text(stmt, 8, sd.ptr, @intCast(sd.len), SQLITE_TRANSIENT);
    } else {
        _ = sqlite3_bind_null(stmt, 8);
    }

    _ = sqlite3_bind_text(stmt, 9, record.upload_date.ptr, @intCast(record.upload_date.len), SQLITE_TRANSIENT);

    if (record.width) |w| {
        _ = sqlite3_bind_int(stmt, 10, w);
    } else {
        _ = sqlite3_bind_null(stmt, 10);
    }

    if (record.height) |h| {
        _ = sqlite3_bind_int(stmt, 11, h);
    } else {
        _ = sqlite3_bind_null(stmt, 11);
    }

    const rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        std.debug.print("Failed to insert photo: {s}\n", .{sqlite3_errmsg(db)});
        return error.SqliteInsertFailed;
    }
}

pub fn updatePhotoDimensions(uuid: []const u8, width: i32, height: i32) !void {
    const io = global_io orelse return error.DbNotInitialized;
    db_mutex.lockUncancelable(io);
    defer db_mutex.unlock(io);

    const db = db_conn orelse return error.DbNotInitialized;

    const sql = "UPDATE photos SET width = ?, height = ? WHERE uuid = ?;";

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, null) != SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = sqlite3_finalize(stmt);

    _ = sqlite3_bind_int(stmt, 1, width);
    _ = sqlite3_bind_int(stmt, 2, height);
    _ = sqlite3_bind_text(stmt, 3, uuid.ptr, @intCast(uuid.len), SQLITE_TRANSIENT);

    const rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        std.debug.print("Failed to update photo dimensions: {s}\n", .{sqlite3_errmsg(db)});
        return error.SqliteUpdateFailed;
    }
}

pub fn getPhotoLocation(uuid: []const u8, allocator: std.mem.Allocator) !?LocationRecord {
    var local_db: ?*sqlite3 = null;
    const rc_open = sqlite3_open_v2(
        "photos.db",
        &local_db,
        SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
        null,
    );
    if (rc_open != SQLITE_OK) {
        if (local_db) |ldb| _ = sqlite3_close(ldb);
        return error.SqliteOpenFailed;
    }
    defer _ = sqlite3_close(local_db);

    const sql = "SELECT username, year, month, extension FROM photos WHERE uuid = ?;";

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(local_db, sql, -1, &stmt, null) != SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = sqlite3_finalize(stmt);

    _ = sqlite3_bind_text(stmt, 1, uuid.ptr, @intCast(uuid.len), SQLITE_TRANSIENT);

    const rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        const username_c = sqlite3_column_text(stmt, 0);
        const year_c = sqlite3_column_text(stmt, 1);
        const month_c = sqlite3_column_text(stmt, 2);
        const extension_c = sqlite3_column_text(stmt, 3);

        const username_len = sqlite3_column_bytes(stmt, 0);
        const year_len = sqlite3_column_bytes(stmt, 1);
        const month_len = sqlite3_column_bytes(stmt, 2);
        const extension_len = sqlite3_column_bytes(stmt, 3);

        return LocationRecord{
            .username = try allocator.dupe(u8, username_c[0..@intCast(username_len)]),
            .year = try allocator.dupe(u8, year_c[0..@intCast(year_len)]),
            .month = try allocator.dupe(u8, month_c[0..@intCast(month_len)]),
            .extension = try allocator.dupe(u8, extension_c[0..@intCast(extension_len)]),
        };
    } else if (rc == SQLITE_DONE) {
        return null;
    } else {
        std.debug.print("Failed to get photo location: {s}\n", .{sqlite3_errmsg(local_db)});
        return error.SqliteSelectFailed;
    }
}

pub fn getUserPhotos(username: []const u8, allocator: std.mem.Allocator) ![]PhotoRecord {
    const io = global_io orelse return error.DbNotInitialized;
    db_mutex.lockUncancelable(io);
    defer db_mutex.unlock(io);

    const db = db_conn orelse return error.DbNotInitialized;

    const sql = "SELECT uuid, username, filename, extension, year, month, day, shooting_date, upload_date, width, height FROM photos WHERE username = ? ORDER BY COALESCE(shooting_date, upload_date) DESC, upload_date DESC;";

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, null) != SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = sqlite3_finalize(stmt);

    _ = sqlite3_bind_text(stmt, 1, username.ptr, @intCast(username.len), SQLITE_TRANSIENT);

    var list = std.ArrayList(PhotoRecord).empty;
    errdefer {
        for (list.items) |r| {
            allocator.free(r.uuid);
            allocator.free(r.username);
            allocator.free(r.filename);
            allocator.free(r.extension);
            allocator.free(r.year);
            allocator.free(r.month);
            allocator.free(r.day);
            if (r.shooting_date) |sd| allocator.free(sd);
            allocator.free(r.upload_date);
        }
        list.deinit(allocator);
    }

    while (true) {
        const rc = sqlite3_step(stmt);
        if (rc == SQLITE_ROW) {
            const uuid_c = sqlite3_column_text(stmt, 0);
            const username_c = sqlite3_column_text(stmt, 1);
            const filename_c = sqlite3_column_text(stmt, 2);
            const extension_c = sqlite3_column_text(stmt, 3);
            const year_c = sqlite3_column_text(stmt, 4);
            const month_c = sqlite3_column_text(stmt, 5);
            const day_c = sqlite3_column_text(stmt, 6);
            const shooting_c = sqlite3_column_text(stmt, 7);
            const upload_c = sqlite3_column_text(stmt, 8);

            const uuid_len = sqlite3_column_bytes(stmt, 0);
            const username_len = sqlite3_column_bytes(stmt, 1);
            const filename_len = sqlite3_column_bytes(stmt, 2);
            const extension_len = sqlite3_column_bytes(stmt, 3);
            const year_len = sqlite3_column_bytes(stmt, 4);
            const month_len = sqlite3_column_bytes(stmt, 5);
            const day_len = sqlite3_column_bytes(stmt, 6);
            const shooting_len = sqlite3_column_bytes(stmt, 7);
            const upload_len = sqlite3_column_bytes(stmt, 8);

            const is_null_width = sqlite3_column_type(stmt, 9) == SQLITE_NULL;
            const width: ?i32 = if (is_null_width) null else sqlite3_column_int(stmt, 9);

            const is_null_height = sqlite3_column_type(stmt, 10) == SQLITE_NULL;
            const height: ?i32 = if (is_null_height) null else sqlite3_column_int(stmt, 10);

            const shooting_date = if (shooting_c != null) try allocator.dupe(u8, shooting_c[0..@intCast(shooting_len)]) else null;

            try list.append(allocator, PhotoRecord{
                .uuid = try allocator.dupe(u8, uuid_c[0..@intCast(uuid_len)]),
                .username = try allocator.dupe(u8, username_c[0..@intCast(username_len)]),
                .filename = try allocator.dupe(u8, filename_c[0..@intCast(filename_len)]),
                .extension = try allocator.dupe(u8, extension_c[0..@intCast(extension_len)]),
                .year = try allocator.dupe(u8, year_c[0..@intCast(year_len)]),
                .month = try allocator.dupe(u8, month_c[0..@intCast(month_len)]),
                .day = try allocator.dupe(u8, day_c[0..@intCast(day_len)]),
                .shooting_date = shooting_date,
                .upload_date = try allocator.dupe(u8, upload_c[0..@intCast(upload_len)]),
                .width = width,
                .height = height,
            });
        } else if (rc == SQLITE_DONE) {
            break;
        } else {
            std.debug.print("Failed to step getUserPhotos: {s}\n", .{sqlite3_errmsg(db)});
            return error.SqliteSelectFailed;
        }
    }

    return try list.toOwnedSlice(allocator);
}

pub fn insertPhotoExif(record: PhotoExifRecord) !void {
    @setEvalBranchQuota(10000);
    const io = global_io orelse return error.DbNotInitialized;
    db_mutex.lockUncancelable(io);
    defer db_mutex.unlock(io);

    const db = db_conn orelse return error.DbNotInitialized;

    const insert_sql = comptime blk: {
        @setEvalBranchQuota(10000);
        var cols: []const u8 = "INSERT INTO photo_exif (uuid";
        var vals: []const u8 = "VALUES (?";
        for (std.meta.fields(PhotoExifRecord)) |field| {
            if (std.mem.eql(u8, field.name, "uuid")) continue;
            cols = cols ++ ", \"" ++ field.name ++ "\"";
            vals = vals ++ ", ?";
        }
        break :blk cols ++ ") " ++ vals ++ ");";
    };

    var stmt: ?*sqlite3_stmt = null;
    if (sqlite3_prepare_v2(db, insert_sql, -1, &stmt, null) != SQLITE_OK) {
        std.debug.print("Failed to prepare EXIF insert statement: {s}\n", .{sqlite3_errmsg(db)});
        return error.SqlitePrepareFailed;
    }
    defer _ = sqlite3_finalize(stmt);

    _ = sqlite3_bind_text(stmt, 1, record.uuid.ptr, @intCast(record.uuid.len), SQLITE_TRANSIENT);
    
    var idx: c_int = 2;
    inline for (std.meta.fields(PhotoExifRecord)) |field| {
        if (!comptime std.mem.eql(u8, field.name, "uuid")) {
            const val_opt = @field(record, field.name);
            if (val_opt) |val| {
                _ = sqlite3_bind_text(stmt, idx, val.ptr, @intCast(val.len), SQLITE_TRANSIENT);
            } else {
                _ = sqlite3_bind_null(stmt, idx);
            }
            idx += 1;
        }
    }

    const rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) {
        std.debug.print("Failed to insert photo EXIF: {s}\n", .{sqlite3_errmsg(db)});
        return error.SqliteInsertFailed;
    }
}

