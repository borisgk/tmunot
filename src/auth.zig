const std = @import("std");
const hmac = std.crypto.auth.hmac.sha2.HmacSha256;
const base64 = std.base64.url_safe_no_pad;
const argon2 = std.crypto.pwhash.argon2;

extern "c" fn time(t: ?*i64) i64;

pub const User = struct {
    username: []const u8,
    password_hash: []const u8,
};

pub const AuthContext = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    jwt_secret: []const u8,
    users: std.StringHashMap(User),
    users_lock: std.Io.RwLock,
    users_file_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, users_file_path: []const u8) !*AuthContext {
        var self = try allocator.create(AuthContext);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .jwt_secret = try initJwtSecret(allocator, io),
            .users = std.StringHashMap(User).init(allocator),
            .users_lock = .init,
            .users_file_path = try allocator.dupe(u8, users_file_path),
        };

        try self.loadUsers();
        return self;
    }

    pub fn deinit(self: *AuthContext) void {
        var it = self.users.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.username);
            self.allocator.free(entry.value_ptr.password_hash);
        }
        self.users.deinit();
        self.allocator.free(self.jwt_secret);
        self.allocator.free(self.users_file_path);
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

    fn loadUsers(self: *AuthContext) !void {
        const cwd = std.Io.Dir.cwd();
        var file = cwd.openFile(self.io, self.users_file_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Create default admin/admin user
                std.debug.print("users.json not found, creating default admin user.\n", .{});
                try self.createUser("admin", "admin");
                try self.saveUsers();
                return;
            }
            return err;
        };
        defer file.close(self.io);

        const stat = try file.stat(self.io);
        if (stat.size == 0) {
            std.debug.print("users.json is empty, creating default admin user.\n", .{});
            try self.createUser("admin", "admin");
            try self.saveUsers();
            return;
        }

        const contents = try self.allocator.alloc(u8, @intCast(stat.size));
        defer self.allocator.free(contents);
        var reader = file.reader(self.io, &.{});
        try reader.interface.readSliceAll(contents);

        const parsed = try std.json.parseFromSlice([]User, self.allocator, contents, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        for (parsed.value) |u| {
            try self.users.put(try self.allocator.dupe(u8, u.username), .{
                .username = try self.allocator.dupe(u8, u.username),
                .password_hash = try self.allocator.dupe(u8, u.password_hash),
            });
        }
    }

    // Assumes users_lock is already held (shared or exclusive)
    fn saveUsersInternal(self: *AuthContext) !void {
        const cwd = std.Io.Dir.cwd();
        var file = try cwd.createFile(self.io, self.users_file_path, .{});
        defer file.close(self.io);

        var user_list = std.ArrayList(User).empty;
        defer user_list.deinit(self.allocator);

        var it = self.users.iterator();
        while (it.next()) |entry| {
            try user_list.append(self.allocator, entry.value_ptr.*);
        }

        var writer = file.writer(self.io, &.{});
        try std.json.Stringify.value(user_list.items, .{ .whitespace = .indent_4 }, &writer.interface);
    }

    pub fn saveUsers(self: *AuthContext) !void {
        self.users_lock.lockSharedUncancelable(self.io);
        defer self.users_lock.unlockShared(self.io);
        try self.saveUsersInternal();
    }

    pub fn createUser(self: *AuthContext, username: []const u8, password: []const u8) !void {
        var out_buf: [128]u8 = undefined;
        const hash = try argon2.strHash(password, .{ .allocator = self.allocator, .params = argon2.Params.interactive_2id }, &out_buf, self.io);
        
        self.users_lock.lockUncancelable(self.io);
        defer self.users_lock.unlock(self.io);

        try self.users.put(try self.allocator.dupe(u8, username), .{
            .username = try self.allocator.dupe(u8, username),
            .password_hash = try self.allocator.dupe(u8, hash),
        });
    }

    pub fn verifyCredentials(self: *AuthContext, username: []const u8, password: []const u8) bool {
        self.users_lock.lockSharedUncancelable(self.io);
        const user_opt = self.users.get(username);
        self.users_lock.unlockShared(self.io);

        const user = user_opt orelse return false;
        // argon2.strVerify needs scratch memory; give it a local arena so it
        // doesn't race on the shared GPA under concurrent login requests.
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        argon2.strVerify(user.password_hash, password, .{ .allocator = arena.allocator() }, self.io) catch {
            return false;
        };
        return true;
    }

    pub fn deleteUser(self: *AuthContext, username: []const u8) !void {
        self.users_lock.lockUncancelable(self.io);
        defer self.users_lock.unlock(self.io);
        if (self.users.get(username)) |user| {
            _ = self.users.remove(username);
            self.allocator.free(user.username); // username is the key as well
            self.allocator.free(user.password_hash);
            try self.saveUsersInternal();
        } else {
            return error.UserNotFound;
        }
    }

    pub fn getUsers(self: *AuthContext, allocator: std.mem.Allocator) ![]const []const u8 {
        self.users_lock.lockSharedUncancelable(self.io);
        defer self.users_lock.unlockShared(self.io);

        var user_list = std.ArrayList([]const u8).empty;
        errdefer user_list.deinit(allocator);

        var it = self.users.iterator();
        while (it.next()) |entry| {
            try user_list.append(allocator, try allocator.dupe(u8, entry.key_ptr.*));
        }

        return user_list.toOwnedSlice(allocator);
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
