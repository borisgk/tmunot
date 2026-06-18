const std = @import("std");
const core = @import("core.zig");

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

pub const VideoMetadataRecord = struct {
    uuid: []const u8,
    codec_name: ?[]const u8 = null,
    width: ?[]const u8 = null,
    height: ?[]const u8 = null,
    duration: ?[]const u8 = null,
    frame_rate: ?[]const u8 = null,
    bit_rate: ?[]const u8 = null,
    format_name: ?[]const u8 = null,
    encoder: ?[]const u8 = null,
    creation_time: ?[]const u8 = null,
    location: ?[]const u8 = null,
};

pub const PhotoExifRecord = struct {
    uuid: []const u8,
    GPSVersionID: ?[]const u8 = null,
    GPSLatitudeRef: ?[]const u8 = null,
    GPSLatitude: ?[]const u8 = null,
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
pub fn insertPhoto(record: PhotoRecord) !void {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(record.username);

    const insert_sql =
        \\INSERT OR REPLACE INTO photos (uuid, username, filename, extension, year, month, day, shooting_date, upload_date, width, height)
        \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ;

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, insert_sql, -1, &stmt, null) != core.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    // Bind parameters
    _ = core.sqlite3_bind_text(stmt, 1, record.uuid.ptr, @intCast(record.uuid.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 2, record.username.ptr, @intCast(record.username.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 3, record.filename.ptr, @intCast(record.filename.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 4, record.extension.ptr, @intCast(record.extension.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 5, record.year.ptr, @intCast(record.year.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 6, record.month.ptr, @intCast(record.month.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 7, record.day.ptr, @intCast(record.day.len), core.SQLITE_TRANSIENT);

    if (record.shooting_date) |sd| {
        _ = core.sqlite3_bind_text(stmt, 8, sd.ptr, @intCast(sd.len), core.SQLITE_TRANSIENT);
    } else {
        _ = core.sqlite3_bind_null(stmt, 8);
    }

    _ = core.sqlite3_bind_text(stmt, 9, record.upload_date.ptr, @intCast(record.upload_date.len), core.SQLITE_TRANSIENT);

    if (record.width) |w| {
        _ = core.sqlite3_bind_int(stmt, 10, w);
    } else {
        _ = core.sqlite3_bind_null(stmt, 10);
    }

    if (record.height) |h| {
        _ = core.sqlite3_bind_int(stmt, 11, h);
    } else {
        _ = core.sqlite3_bind_null(stmt, 11);
    }

    const rc = core.sqlite3_step(stmt);
    if (rc != core.SQLITE_DONE) {
        std.debug.print("Failed to insert photo: {s}\n", .{core.sqlite3_errmsg(db)});
        return error.SqliteInsertFailed;
    }
}

pub fn updatePhotoDimensions(username: []const u8, uuid: []const u8, width: i32, height: i32) !void {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const sql = "UPDATE photos SET width = ?, height = ? WHERE uuid = ?;";

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, sql, -1, &stmt, null) != core.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_int(stmt, 1, width);
    _ = core.sqlite3_bind_int(stmt, 2, height);
    _ = core.sqlite3_bind_text(stmt, 3, uuid.ptr, @intCast(uuid.len), core.SQLITE_TRANSIENT);

    const rc = core.sqlite3_step(stmt);
    if (rc != core.SQLITE_DONE) {
        std.debug.print("Failed to update photo dimensions: {s}\n", .{core.sqlite3_errmsg(db)});
        return error.SqliteUpdateFailed;
    }
}

pub fn getPhotoLocation(uuid: []const u8, allocator: std.mem.Allocator) !?LocationRecord {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    var dir = std.Io.Dir.cwd().openDir(io, core.global_db_dir, .{ .iterate = true }) catch return null;
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".db")) {
            const username = entry.name[0 .. entry.name.len - 3];
            const db = core.getDb(username) catch continue;

            const sql = "SELECT username, year, month, extension FROM photos WHERE uuid = ?;";
            var stmt: ?*core.sqlite3_stmt = null;
            if (core.sqlite3_prepare_v2(db, sql, -1, &stmt, null) != core.SQLITE_OK) continue;
            defer _ = core.sqlite3_finalize(stmt);

            _ = core.sqlite3_bind_text(stmt, 1, uuid.ptr, @intCast(uuid.len), core.SQLITE_TRANSIENT);

            const rc = core.sqlite3_step(stmt);
            if (rc == core.SQLITE_ROW) {
                const username_c = core.sqlite3_column_text(stmt, 0);
                const year_c = core.sqlite3_column_text(stmt, 1);
                const month_c = core.sqlite3_column_text(stmt, 2);
                const extension_c = core.sqlite3_column_text(stmt, 3);

                const username_len = core.sqlite3_column_bytes(stmt, 0);
                const year_len = core.sqlite3_column_bytes(stmt, 1);
                const month_len = core.sqlite3_column_bytes(stmt, 2);
                const extension_len = core.sqlite3_column_bytes(stmt, 3);

                return LocationRecord{
                    .username = try allocator.dupe(u8, username_c[0..@intCast(username_len)]),
                    .year = try allocator.dupe(u8, year_c[0..@intCast(year_len)]),
                    .month = try allocator.dupe(u8, month_c[0..@intCast(month_len)]),
                    .extension = try allocator.dupe(u8, extension_c[0..@intCast(extension_len)]),
                };
            }
        }
    }
    return null;
}

/// Like getPhotoLocation but queries only the specified user's database.
/// This is O(1) instead of O(N users) and enforces ownership by design.
pub fn getPhotoLocationForUser(username: []const u8, uuid: []const u8, allocator: std.mem.Allocator) !?LocationRecord {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = core.getDb(username) catch return null;

    const sql = "SELECT username, year, month, extension FROM photos WHERE uuid = ?;";
    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, sql, -1, &stmt, null) != core.SQLITE_OK) return null;
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, uuid.ptr, @intCast(uuid.len), core.SQLITE_TRANSIENT);

    const rc = core.sqlite3_step(stmt);
    if (rc == core.SQLITE_ROW) {
        const username_c = core.sqlite3_column_text(stmt, 0);
        const year_c = core.sqlite3_column_text(stmt, 1);
        const month_c = core.sqlite3_column_text(stmt, 2);
        const extension_c = core.sqlite3_column_text(stmt, 3);

        const username_len = core.sqlite3_column_bytes(stmt, 0);
        const year_len = core.sqlite3_column_bytes(stmt, 1);
        const month_len = core.sqlite3_column_bytes(stmt, 2);
        const extension_len = core.sqlite3_column_bytes(stmt, 3);

        return LocationRecord{
            .username = try allocator.dupe(u8, username_c[0..@intCast(username_len)]),
            .year = try allocator.dupe(u8, year_c[0..@intCast(year_len)]),
            .month = try allocator.dupe(u8, month_c[0..@intCast(month_len)]),
            .extension = try allocator.dupe(u8, extension_c[0..@intCast(extension_len)]),
        };
    }
    return null;
}

pub fn getUserPhotos(username: []const u8, allocator: std.mem.Allocator) ![]PhotoRecord {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const sql = "SELECT uuid, username, filename, extension, year, month, day, shooting_date, upload_date, width, height FROM photos WHERE username = ? ORDER BY COALESCE(shooting_date, upload_date) DESC, upload_date DESC;";

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, sql, -1, &stmt, null) != core.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, username.ptr, @intCast(username.len), core.SQLITE_TRANSIENT);

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
        const rc = core.sqlite3_step(stmt);
        if (rc == core.SQLITE_ROW) {
            const uuid_c = core.sqlite3_column_text(stmt, 0);
            const username_c = core.sqlite3_column_text(stmt, 1);
            const filename_c = core.sqlite3_column_text(stmt, 2);
            const extension_c = core.sqlite3_column_text(stmt, 3);
            const year_c = core.sqlite3_column_text(stmt, 4);
            const month_c = core.sqlite3_column_text(stmt, 5);
            const day_c = core.sqlite3_column_text(stmt, 6);
            const shooting_c = core.sqlite3_column_text(stmt, 7);
            const upload_c = core.sqlite3_column_text(stmt, 8);

            const uuid_len = core.sqlite3_column_bytes(stmt, 0);
            const username_len = core.sqlite3_column_bytes(stmt, 1);
            const filename_len = core.sqlite3_column_bytes(stmt, 2);
            const extension_len = core.sqlite3_column_bytes(stmt, 3);
            const year_len = core.sqlite3_column_bytes(stmt, 4);
            const month_len = core.sqlite3_column_bytes(stmt, 5);
            const day_len = core.sqlite3_column_bytes(stmt, 6);
            const shooting_len = core.sqlite3_column_bytes(stmt, 7);
            const upload_len = core.sqlite3_column_bytes(stmt, 8);

            const is_null_width = core.sqlite3_column_type(stmt, 9) == core.SQLITE_NULL;
            const width: ?i32 = if (is_null_width) null else core.sqlite3_column_int(stmt, 9);

            const is_null_height = core.sqlite3_column_type(stmt, 10) == core.SQLITE_NULL;
            const height: ?i32 = if (is_null_height) null else core.sqlite3_column_int(stmt, 10);

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
        } else if (rc == core.SQLITE_DONE) {
            break;
        } else {
            std.debug.print("Failed to step getUserPhotos: {s}\n", .{core.sqlite3_errmsg(db)});
            return error.SqliteSelectFailed;
        }
    }

    return try list.toOwnedSlice(allocator);
}

pub fn getUserPhotoYears(username: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const sql = "SELECT DISTINCT year FROM photos WHERE username = ? ORDER BY year DESC;";

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, sql, -1, &stmt, null) != core.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, username.ptr, @intCast(username.len), core.SQLITE_TRANSIENT);

    var list = std.ArrayList([]const u8).empty;
    errdefer {
        for (list.items) |y| allocator.free(y);
        list.deinit(allocator);
    }

    while (true) {
        const rc = core.sqlite3_step(stmt);
        if (rc == core.SQLITE_ROW) {
            const year_c = core.sqlite3_column_text(stmt, 0);
            const year_len = core.sqlite3_column_bytes(stmt, 0);
            if (year_c) |yc| {
                try list.append(allocator, try allocator.dupe(u8, yc[0..@intCast(year_len)]));
            }
        } else if (rc == core.SQLITE_DONE) {
            break;
        } else {
            return error.SqliteSelectFailed;
        }
    }

    return try list.toOwnedSlice(allocator);
}

pub fn getUserPhotosFiltered(username: []const u8, year_filter: ?[]const u8, allocator: std.mem.Allocator) ![]PhotoRecord {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const sql = if (year_filter) |yf|
        if (std.mem.eql(u8, yf, "all"))
            "SELECT uuid, username, filename, extension, year, month, day, shooting_date, upload_date, width, height FROM photos WHERE username = ? ORDER BY COALESCE(shooting_date, upload_date) DESC, upload_date DESC;"
        else
            "SELECT uuid, username, filename, extension, year, month, day, shooting_date, upload_date, width, height FROM photos WHERE username = ? AND year = ? ORDER BY COALESCE(shooting_date, upload_date) DESC, upload_date DESC;"
    else
        "SELECT uuid, username, filename, extension, year, month, day, shooting_date, upload_date, width, height FROM photos WHERE username = ? ORDER BY COALESCE(shooting_date, upload_date) DESC, upload_date DESC;";

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, sql, -1, &stmt, null) != core.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, username.ptr, @intCast(username.len), core.SQLITE_TRANSIENT);
    if (year_filter) |yf| {
        if (!std.mem.eql(u8, yf, "all")) {
            _ = core.sqlite3_bind_text(stmt, 2, yf.ptr, @intCast(yf.len), core.SQLITE_TRANSIENT);
        }
    }

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
        const rc = core.sqlite3_step(stmt);
        if (rc == core.SQLITE_ROW) {
            const uuid_c = core.sqlite3_column_text(stmt, 0);
            const username_c = core.sqlite3_column_text(stmt, 1);
            const filename_c = core.sqlite3_column_text(stmt, 2);
            const extension_c = core.sqlite3_column_text(stmt, 3);
            const year_c = core.sqlite3_column_text(stmt, 4);
            const month_c = core.sqlite3_column_text(stmt, 5);
            const day_c = core.sqlite3_column_text(stmt, 6);
            const shooting_c = core.sqlite3_column_text(stmt, 7);
            const upload_c = core.sqlite3_column_text(stmt, 8);

            const uuid_len = core.sqlite3_column_bytes(stmt, 0);
            const username_len = core.sqlite3_column_bytes(stmt, 1);
            const filename_len = core.sqlite3_column_bytes(stmt, 2);
            const extension_len = core.sqlite3_column_bytes(stmt, 3);
            const year_len = core.sqlite3_column_bytes(stmt, 4);
            const month_len = core.sqlite3_column_bytes(stmt, 5);
            const day_len = core.sqlite3_column_bytes(stmt, 6);
            const shooting_len = core.sqlite3_column_bytes(stmt, 7);
            const upload_len = core.sqlite3_column_bytes(stmt, 8);

            const is_null_width = core.sqlite3_column_type(stmt, 9) == core.SQLITE_NULL;
            const width: ?i32 = if (is_null_width) null else core.sqlite3_column_int(stmt, 9);

            const is_null_height = core.sqlite3_column_type(stmt, 10) == core.SQLITE_NULL;
            const height: ?i32 = if (is_null_height) null else core.sqlite3_column_int(stmt, 10);

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
        } else if (rc == core.SQLITE_DONE) {
            break;
        } else {
            std.debug.print("Failed to step getUserPhotosFiltered: {s}\n", .{core.sqlite3_errmsg(db)});
            return error.SqliteSelectFailed;
        }
    }

    return try list.toOwnedSlice(allocator);
}

pub fn insertPhotoExif(username: []const u8, record: PhotoExifRecord) !void {
    @setEvalBranchQuota(10000);
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const insert_sql = comptime blk: {
        @setEvalBranchQuota(10000);
        var cols: []const u8 = "INSERT OR REPLACE INTO photo_exif (uuid";
        var vals: []const u8 = "VALUES (?";
        for (std.meta.fieldNames(PhotoExifRecord)) |field_name| {
            if (std.mem.eql(u8, field_name, "uuid")) continue;
            cols = cols ++ ", \"" ++ field_name ++ "\"";
            vals = vals ++ ", ?";
        }
        break :blk cols ++ ") " ++ vals ++ ");";
    };

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, insert_sql, -1, &stmt, null) != core.SQLITE_OK) {
        std.debug.print("Failed to prepare EXIF insert statement: {s}\n", .{core.sqlite3_errmsg(db)});
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, record.uuid.ptr, @intCast(record.uuid.len), core.SQLITE_TRANSIENT);
    
    var idx: c_int = 2;
    inline for (comptime std.meta.fieldNames(PhotoExifRecord)) |field_name| {
        if (!comptime std.mem.eql(u8, field_name, "uuid")) {
            const val_opt = @field(record, field_name);
            if (val_opt) |val| {
                _ = core.sqlite3_bind_text(stmt, idx, val.ptr, @intCast(val.len), core.SQLITE_TRANSIENT);
            } else {
                _ = core.sqlite3_bind_null(stmt, idx);
            }
            idx += 1;
        }
    }

    const rc = core.sqlite3_step(stmt);
    if (rc != core.SQLITE_DONE) {
        std.debug.print("Failed to insert photo EXIF: {s}\n", .{core.sqlite3_errmsg(db)});
        return error.SqliteInsertFailed;
    }
}

pub fn getPhotoExif(username: []const u8, uuid: []const u8, allocator: std.mem.Allocator) !?PhotoExifRecord {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const select_sql = comptime blk: {
        var q: []const u8 = "SELECT ";
        var first = true;
        for (std.meta.fieldNames(PhotoExifRecord)) |field_name| {
            if (!first) q = q ++ ", ";
            q = q ++ "\"" ++ field_name ++ "\"";
            first = false;
        }
        break :blk q ++ " FROM photo_exif WHERE uuid = ?;";
    };

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, select_sql, -1, &stmt, null) != core.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, uuid.ptr, @intCast(uuid.len), core.SQLITE_TRANSIENT);

    const rc = core.sqlite3_step(stmt);
    if (rc == core.SQLITE_ROW) {
        var record: PhotoExifRecord = undefined;
        var idx: c_int = 0;
        inline for (comptime std.meta.fieldNames(PhotoExifRecord)) |field_name| {
            if (comptime std.mem.eql(u8, field_name, "uuid")) {
                if (core.sqlite3_column_type(stmt, idx) == core.SQLITE_NULL) {
                    return error.MissingUuid;
                } else {
                    const text_ptr = core.sqlite3_column_text(stmt, idx);
                    const text_len = core.sqlite3_column_bytes(stmt, idx);
                    if (text_ptr != null) {
                        @field(record, field_name) = try allocator.dupe(u8, text_ptr[0..@intCast(text_len)]);
                    } else {
                        return error.MissingUuid;
                    }
                }
            } else {
                if (core.sqlite3_column_type(stmt, idx) == core.SQLITE_NULL) {
                    @field(record, field_name) = null;
                } else {
                    const text_ptr = core.sqlite3_column_text(stmt, idx);
                    const text_len = core.sqlite3_column_bytes(stmt, idx);
                    if (text_ptr != null) {
                        @field(record, field_name) = try allocator.dupe(u8, text_ptr[0..@intCast(text_len)]);
                    } else {
                        @field(record, field_name) = null;
                    }
                }
            }
            idx += 1;
        }
        return record;
    }

    return null;
}

pub fn insertVideoMetadata(username: []const u8, record: VideoMetadataRecord) !void {
    @setEvalBranchQuota(10000);
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const insert_sql = comptime blk: {
        @setEvalBranchQuota(10000);
        var cols: []const u8 = "INSERT OR REPLACE INTO video_metadata (uuid";
        var vals: []const u8 = "VALUES (?";
        for (std.meta.fieldNames(VideoMetadataRecord)) |field_name| {
            if (std.mem.eql(u8, field_name, "uuid")) continue;
            cols = cols ++ ", \"" ++ field_name ++ "\"";
            vals = vals ++ ", ?";
        }
        break :blk cols ++ ") " ++ vals ++ ");";
    };

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, insert_sql, -1, &stmt, null) != core.SQLITE_OK) {
        std.debug.print("Failed to prepare VideoMetadata insert statement: {s}\n", .{core.sqlite3_errmsg(db)});
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, record.uuid.ptr, @intCast(record.uuid.len), core.SQLITE_TRANSIENT);
    
    var idx: c_int = 2;
    inline for (comptime std.meta.fieldNames(VideoMetadataRecord)) |field_name| {
        if (!comptime std.mem.eql(u8, field_name, "uuid")) {
            const val_opt = @field(record, field_name);
            if (val_opt) |val| {
                _ = core.sqlite3_bind_text(stmt, idx, val.ptr, @intCast(val.len), core.SQLITE_TRANSIENT);
            } else {
                _ = core.sqlite3_bind_null(stmt, idx);
            }
            idx += 1;
        }
    }

    const rc = core.sqlite3_step(stmt);
    if (rc != core.SQLITE_DONE) {
        std.debug.print("Failed to insert video metadata: {s}\n", .{core.sqlite3_errmsg(db)});
        return error.SqliteInsertFailed;
    }
}

pub fn getVideoMetadata(username: []const u8, uuid: []const u8, allocator: std.mem.Allocator) !?VideoMetadataRecord {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const query_sql = comptime blk: {
        @setEvalBranchQuota(10000);
        var q: []const u8 = "SELECT uuid";
        for (std.meta.fieldNames(VideoMetadataRecord)) |field_name| {
            if (std.mem.eql(u8, field_name, "uuid")) continue;
            q = q ++ ", \"" ++ field_name ++ "\"";
        }
        break :blk q ++ " FROM video_metadata WHERE uuid = ?;";
    };

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, query_sql, -1, &stmt, null) != core.SQLITE_OK) {
        std.debug.print("Failed to prepare VideoMetadata select statement: {s}\n", .{core.sqlite3_errmsg(db)});
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, uuid.ptr, @intCast(uuid.len), core.SQLITE_TRANSIENT);

    if (core.sqlite3_step(stmt) == core.SQLITE_ROW) {
        var record: VideoMetadataRecord = undefined;
        
        inline for (comptime std.meta.fieldNames(VideoMetadataRecord)) |field_name| {
            if (comptime !std.mem.eql(u8, field_name, "uuid")) {
                @field(record, field_name) = null;
            }
        }

        var idx: c_int = 0;
        inline for (comptime std.meta.fieldNames(VideoMetadataRecord)) |field_name| {
            if (comptime std.mem.eql(u8, field_name, "uuid")) {
                const text_ptr = core.sqlite3_column_text(stmt, idx);
                const text_len = core.sqlite3_column_bytes(stmt, idx);
                if (text_ptr != null) {
                    record.uuid = try allocator.dupe(u8, text_ptr[0..@intCast(text_len)]);
                }
            } else {
                if (core.sqlite3_column_type(stmt, idx) != core.SQLITE_NULL) {
                    const text_ptr = core.sqlite3_column_text(stmt, idx);
                    const text_len = core.sqlite3_column_bytes(stmt, idx);
                    if (text_ptr != null) {
                        @field(record, field_name) = try allocator.dupe(u8, text_ptr[0..@intCast(text_len)]);
                    } else {
                        @field(record, field_name) = null;
                    }
                }
            }
            idx += 1;
        }
        return record;
    }

    return null;
}

pub fn deletePhoto(username: []const u8, uuid: []const u8) !void {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const delete_sql = "DELETE FROM photos WHERE uuid = ?;";

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, delete_sql, -1, &stmt, null) != core.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, uuid.ptr, @intCast(uuid.len), core.SQLITE_TRANSIENT);

    const rc = core.sqlite3_step(stmt);
    if (rc != core.SQLITE_DONE) {
        std.debug.print("Failed to delete photo: {s}\n", .{core.sqlite3_errmsg(db)});
        return error.SqliteDeleteFailed;
    }
}

pub fn updatePhotoDate(username: []const u8, uuid: []const u8, year: []const u8, month: []const u8, day: []const u8, shooting_date: []const u8) !void {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const update_sql = "UPDATE photos SET year = ?, month = ?, day = ?, shooting_date = ? WHERE uuid = ?;";

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, update_sql, -1, &stmt, null) != core.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, year.ptr, @intCast(year.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 2, month.ptr, @intCast(month.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 3, day.ptr, @intCast(day.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 4, shooting_date.ptr, @intCast(shooting_date.len), core.SQLITE_TRANSIENT);
    _ = core.sqlite3_bind_text(stmt, 5, uuid.ptr, @intCast(uuid.len), core.SQLITE_TRANSIENT);

    const rc = core.sqlite3_step(stmt);
    if (rc != core.SQLITE_DONE) {
        std.debug.print("Failed to update photo date: {s}\n", .{core.sqlite3_errmsg(db)});
        return error.SqliteUpdateFailed;
    }
}

pub fn getPhotoDate(username: []const u8, uuid: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    const io = core.global_io orelse return error.DbNotInitialized;
    core.db_mutex.lockUncancelable(io);
    defer core.db_mutex.unlock(io);

    const db = try core.getDb(username);

    const sql = "SELECT COALESCE(shooting_date, upload_date) FROM photos WHERE uuid = ?;";

    var stmt: ?*core.sqlite3_stmt = null;
    if (core.sqlite3_prepare_v2(db, sql, -1, &stmt, null) != core.SQLITE_OK) {
        return error.SqlitePrepareFailed;
    }
    defer _ = core.sqlite3_finalize(stmt);

    _ = core.sqlite3_bind_text(stmt, 1, uuid.ptr, @intCast(uuid.len), core.SQLITE_TRANSIENT);

    const rc = core.sqlite3_step(stmt);
    if (rc == core.SQLITE_ROW) {
        const date_c = core.sqlite3_column_text(stmt, 0);
        const date_len = core.sqlite3_column_bytes(stmt, 0);
        if (date_c != null) {
            return try allocator.dupe(u8, date_c[0..@intCast(date_len)]);
        }
    }
    return null;
}

