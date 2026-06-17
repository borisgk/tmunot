const std = @import("std");
const hmac = std.crypto.auth.hmac.sha2.HmacSha256;
const base64 = std.base64.url_safe_no_pad;
const argon2 = std.crypto.pwhash.argon2;
const db = @import("db.zig");

extern "c" fn time(t: ?*i64) i64;

pub const User = struct {
    username: []const u8,
    password_hash: []const u8,
    real_name: []const u8 = "",
};

pub const PublicUser = struct {
    username: []const u8,
    real_name: []const u8,
    is_admin: bool,
    avatar_ext: ?[]const u8,
};

pub const AuthContext = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    jwt_secret: []const u8,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, users_file_path: []const u8) !*AuthContext {
        var self = try allocator.create(AuthContext);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .jwt_secret = try initJwtSecret(allocator, io),
        };

        const db_path = "users.db";
        try db.initUsersDb(allocator, io, db_path);

        try self.migrateFromJSON(users_file_path);

        // Ensure admin exists
        const users_list = try db.getUsers(allocator);
        defer {
            for (users_list) |u| {
                allocator.free(u.username);
                allocator.free(u.password_hash);
                allocator.free(u.real_name);
                if (u.avatar_ext) |ext| allocator.free(ext);
            }
            allocator.free(users_list);
        }

        if (users_list.len == 0) {
            std.debug.print("users.db is empty, creating default admin user.\n", .{});
            try self.createUser("admin", "admin", "Administrator", true);
        }

        return self;
    }

    pub fn deinit(self: *AuthContext) void {
        db.deinitUsersDb();
        self.allocator.free(self.jwt_secret);
        self.allocator.destroy(self);
    }

    fn initJwtSecret(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
        if (std.c.getenv("JWT_SECRET_KEY")) |env_secret_c| {
            const env_secret = std.mem.span(env_secret_c);
            return allocator.dupe(u8, env_secret);
        }

        const secret_file_path = "jwt_secret.bin";
        const cwd = std.Io.Dir.cwd();

        // 1. Try to open and read existing secret
        if (cwd.openFile(io, secret_file_path, .{})) |file| {
            defer file.close(io);
            const stat = file.stat(io) catch |err| {
                std.debug.print("Failed to stat secret file: {}\n", .{err});
                return error.SecretFileError;
            };
            if (stat.size == 32) {
                var secret_buf: [32]u8 = undefined;
                var reader = file.reader(io, &.{});
                reader.interface.readSliceAll(&secret_buf) catch |err| {
                    std.debug.print("Failed to read secret file: {}\n", .{err});
                    return error.SecretFileError;
                };
                std.debug.print("Loaded persisted JWT secret key from {s}\n", .{secret_file_path});
                return allocator.dupe(u8, &secret_buf);
            }
        } else |err| {
            if (err != error.FileNotFound) {
                std.debug.print("Failed to open secret file: {}\n", .{err});
            }
        }

        // 2. Generate and persist new secret
        std.debug.print("Generating new JWT secret key and persisting to {s}\n", .{secret_file_path});
        var secret: [32]u8 = undefined;
        try io.randomSecure(&secret);

        var file = try cwd.createFile(io, secret_file_path, .{});
        defer file.close(io);
        var writer = file.writer(io, &.{});
        try writer.interface.writeAll(&secret);

        return allocator.dupe(u8, &secret);
    }

    fn migrateFromJSON(self: *AuthContext, json_path: []const u8) !void {
        const cwd = std.Io.Dir.cwd();
        var file = cwd.openFile(self.io, json_path, .{}) catch {
            return; // no json file or error, skip
        };
        defer file.close(self.io);

        const stat = file.stat(self.io) catch return;
        if (stat.size == 0) return;

        const contents = try self.allocator.alloc(u8, @intCast(stat.size));
        defer self.allocator.free(contents);
        var reader = file.reader(self.io, &.{});
        reader.interface.readSliceAll(contents) catch return;

        const parsed = std.json.parseFromSlice([]User, self.allocator, contents, .{ .ignore_unknown_fields = true }) catch return;
        defer parsed.deinit();

        for (parsed.value) |u| {
            const existing = db.getUser(u.username, self.allocator) catch null;
            if (existing) |e| {
                self.allocator.free(e.username);
                self.allocator.free(e.password_hash);
                self.allocator.free(e.real_name);
                if (e.avatar_ext) |ext| self.allocator.free(ext);
                continue;
            }

            const is_admin = std.mem.eql(u8, u.username, "admin");
            db.insertUser(u.username, u.password_hash, u.real_name, is_admin, null) catch |e| {
                std.debug.print("Failed to migrate user {s}: {}\n", .{u.username, e});
            };
        }
        
        cwd.rename(json_path, cwd, "users.json.bak", self.io) catch {};
    }

    pub fn createUser(self: *AuthContext, username: []const u8, password: []const u8, real_name: []const u8, is_admin: bool) !void {
        const existing = try db.getUser(username, self.allocator);
        if (existing) |e| {
            self.allocator.free(e.username);
            self.allocator.free(e.password_hash);
            self.allocator.free(e.real_name);
            if (e.avatar_ext) |ext| self.allocator.free(ext);
            return error.UserAlreadyExists;
        }

        var out_buf: [128]u8 = undefined;
        const hash = try argon2.strHash(password, .{ .allocator = self.allocator, .params = argon2.Params.interactive_2id }, &out_buf, self.io);
        
        try db.insertUser(username, hash, real_name, is_admin, null);
    }

    pub fn verifyCredentials(self: *AuthContext, username: []const u8, password: []const u8) bool {
        const user_opt = db.getUser(username, self.allocator) catch return false;
        const user = user_opt orelse return false;
        defer {
            self.allocator.free(user.username);
            self.allocator.free(user.password_hash);
            self.allocator.free(user.real_name);
            if (user.avatar_ext) |ext| self.allocator.free(ext);
        }

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        argon2.strVerify(user.password_hash, password, .{ .allocator = arena.allocator() }, self.io) catch {
            return false;
        };
        return true;
    }

    pub fn deleteUser(self: *AuthContext, username: []const u8) !void {
        _ = self;
        try db.deleteUser(username);
    }

    pub fn getUsers(self: *AuthContext, allocator: std.mem.Allocator) ![]PublicUser {
        _ = self;
        const db_users = try db.getUsers(allocator);
        var user_list = std.ArrayList(PublicUser).empty;
        errdefer user_list.deinit(allocator);

        for (db_users) |u| {
            try user_list.append(allocator, .{
                .username = u.username,
                .real_name = u.real_name,
                .is_admin = u.is_admin,
                .avatar_ext = u.avatar_ext,
            });
            allocator.free(u.password_hash); // Free what we don't need
        }
        allocator.free(db_users);

        return user_list.toOwnedSlice(allocator);
    }

    pub fn isAdmin(self: *AuthContext, username: []const u8) bool {
        if (db.getUser(username, self.allocator) catch null) |user| {
            defer {
                self.allocator.free(user.username);
                self.allocator.free(user.password_hash);
                self.allocator.free(user.real_name);
                if (user.avatar_ext) |ext| self.allocator.free(ext);
            }
            return user.is_admin;
        }
        return false;
    }

    pub fn editUser(self: *AuthContext, username: []const u8, new_password: ?[]const u8, new_real_name: ?[]const u8, new_is_admin: ?bool, new_avatar_ext: ?[]const u8) !void {
        var new_hash_opt: ?[]const u8 = null;
        if (new_password) |pwd| {
            if (pwd.len > 0) {
                var out_buf: [128]u8 = undefined;
                const hash = try argon2.strHash(pwd, .{ .allocator = self.allocator, .params = argon2.Params.interactive_2id }, &out_buf, self.io);
                new_hash_opt = try self.allocator.dupe(u8, hash);
            }
        }
        defer {
            if (new_hash_opt) |hash| self.allocator.free(hash);
        }
        
        try db.updateUser(username, new_hash_opt, new_real_name, new_is_admin, new_avatar_ext);
    }

    pub fn generateJwt(self: *AuthContext, username: []const u8) ![]u8 {
        // Use a local arena for all scratch buffers; only the final token is
        // returned and must be freed by the caller (using the caller's allocator).
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const header = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}";
        const exp = time(null) + 3600 * 24; // 24 hours

        const payload = try std.fmt.allocPrint(a, "{{\"sub\":\"{s}\",\"exp\":{d}}}", .{ username, exp });

        const header_b64 = try a.alloc(u8, base64.Encoder.calcSize(header.len));
        _ = base64.Encoder.encode(header_b64, header);

        const payload_b64 = try a.alloc(u8, base64.Encoder.calcSize(payload.len));
        _ = base64.Encoder.encode(payload_b64, payload);

        const msg = try std.fmt.allocPrint(a, "{s}.{s}", .{ header_b64, payload_b64 });

        var mac: [hmac.mac_length]u8 = undefined;
        hmac.create(&mac, msg, self.jwt_secret);

        const sig_b64 = try a.alloc(u8, base64.Encoder.calcSize(mac.len));
        _ = base64.Encoder.encode(sig_b64, &mac);

        // Duplicate the final token into the shared allocator so the caller can
        // manage its lifetime independently of the local arena.
        return self.allocator.dupe(u8, try std.fmt.allocPrint(a, "{s}.{s}", .{ msg, sig_b64 }));
    }

    pub fn verifyJwt(self: *AuthContext, token: []const u8) bool {
        // Local arena for all scratch allocations — never touches the shared GPA.
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var parts = std.mem.splitScalar(u8, token, '.');
        const header_b64 = parts.next() orelse return false;
        const payload_b64 = parts.next() orelse return false;
        const sig_b64 = parts.next() orelse return false;
        if (parts.next() != null) return false;

        const msg = std.fmt.allocPrint(a, "{s}.{s}", .{ header_b64, payload_b64 }) catch return false;

        var mac: [hmac.mac_length]u8 = undefined;
        hmac.create(&mac, msg, self.jwt_secret);

        const expected_sig_b64 = a.alloc(u8, base64.Encoder.calcSize(mac.len)) catch return false;
        _ = base64.Encoder.encode(expected_sig_b64, &mac);

        if (!std.mem.eql(u8, sig_b64, expected_sig_b64)) return false;

        const payload = a.alloc(u8, base64.Decoder.calcSizeForSlice(payload_b64) catch return false) catch return false;
        base64.Decoder.decode(payload, payload_b64) catch return false;

        const exp_idx = std.mem.indexOf(u8, payload, "\"exp\":") orelse return false;
        var end_idx = exp_idx + 6;
        while (end_idx < payload.len and std.ascii.isDigit(payload[end_idx])) : (end_idx += 1) {}

        const exp_str = payload[exp_idx + 6 .. end_idx];
        const exp = std.fmt.parseInt(i64, exp_str, 10) catch return false;

        if (time(null) > exp) return false;

        return true;
    }

    pub fn generateCsrfToken(self: *AuthContext, allocator: std.mem.Allocator) ![]u8 {
        var token_bytes: [32]u8 = undefined;
        try self.io.randomSecure(&token_bytes);
        const token_b64 = try allocator.alloc(u8, base64.Encoder.calcSize(token_bytes.len));
        _ = base64.Encoder.encode(token_b64, &token_bytes);
        return token_b64;
    }

    pub fn getUsernameFromJwt(self: *AuthContext, token: []const u8, allocator: std.mem.Allocator) ?[]const u8 {
        if (!self.verifyJwt(token)) return null;

        // Local arena for decoding scratch — result is duped into caller's allocator.
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var parts = std.mem.splitScalar(u8, token, '.');
        _ = parts.next() orelse return null;
        const payload_b64 = parts.next() orelse return null;

        const payload_size = base64.Decoder.calcSizeForSlice(payload_b64) catch return null;
        const payload = a.alloc(u8, payload_size) catch return null;

        base64.Decoder.decode(payload, payload_b64) catch return null;

        // Parse username from payload: {"sub":"username","exp":123456}
        const sub_idx = std.mem.indexOf(u8, payload, "\"sub\":\"") orelse return null;
        const start = sub_idx + 7;
        const end = std.mem.indexOfPos(u8, payload, start, "\"") orelse return null;

        return allocator.dupe(u8, payload[start..end]) catch null;
    }
};
