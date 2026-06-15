const std = @import("std");
const db = @import("../../db.zig");
const server = @import("../../server.zig");

pub const shared_modals_html = @embedFile("../../templates/components/modals.html");

pub fn replacePlaceholder(allocator: std.mem.Allocator, html: []const u8, placeholder: []const u8, replacement: []const u8) ![]u8 {
    const size = std.mem.replacementSize(u8, html, placeholder, replacement);
    const new_html = try allocator.alloc(u8, size);
    _ = std.mem.replace(u8, html, placeholder, replacement, new_html);
    return new_html;
}

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

pub fn renderMediaCard(alloc: std.mem.Allocator, r: db.PhotoRecord, idx: usize) ![]const u8 {
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
    
    const safe_filename = try server.htmlEscape(alloc, r.filename);
    defer alloc.free(safe_filename);
    
    var html: []const u8 = if (is_video) @embedFile("../../templates/components/card_video.html") else @embedFile("../../templates/components/card_image.html");
    
    // Replace all placeholders
    html = try replacePlaceholder(alloc, html, "<!-- UUID -->", r.uuid);
    html = try replacePlaceholder(alloc, html, "<!-- EXTENSION -->", r.extension);
    html = try replacePlaceholder(alloc, html, "<!-- YEAR -->", ym.year);
    html = try replacePlaceholder(alloc, html, "<!-- MONTH -->", ym.month);
    html = try replacePlaceholder(alloc, html, "<!-- DATE -->", shooting_date_str);
    
    var buf_ratio: [32]u8 = undefined;
    const ratio_str = try std.fmt.bufPrint(&buf_ratio, "{d:.4}", .{ratio});
    html = try replacePlaceholder(alloc, html, "<!-- RATIO -->", ratio_str);
    
    html = try replacePlaceholder(alloc, html, "<!-- LOADING_ATTR -->", loading_attr);
    html = try replacePlaceholder(alloc, html, "<!-- PRIORITY_ATTR -->", priority_attr);
    html = try replacePlaceholder(alloc, html, "<!-- SAFE_FILENAME -->", safe_filename);

    return html;
}

