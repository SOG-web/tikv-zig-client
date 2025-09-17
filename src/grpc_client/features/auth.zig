const std = @import("std");
const crypto = std.crypto;

pub const AuthError = error{
    InvalidToken,
    Unauthorized,
    TokenExpired,
};

pub const Auth = struct {
    const TokenHeader = struct {
        alg: []const u8,
        typ: []const u8,
    };

    const TokenPayload = struct {
        sub: []const u8,
        exp: i64,
        iat: i64,
    };

    secret_key: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, secret_key: []const u8) Auth {
        return .{
            .allocator = allocator,
            .secret_key = secret_key,
        };
    }

    pub fn verifyToken(self: *Auth, token: []const u8) !void {
        // Basic JWT verification
        var parts = std.mem.splitAny(u8, token, ".");
        const header_b64 = parts.next() orelse return AuthError.InvalidToken;
        const payload_b64 = parts.next() orelse return AuthError.InvalidToken;
        const signature = parts.next() orelse return AuthError.InvalidToken;

        // Verify signature
        var hash = crypto.auth.hmac.sha2.HmacSha256.init(self.secret_key);
        hash.update(header_b64);
        hash.update(".");
        hash.update(payload_b64);

        var expected_signature: [crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
        hash.final(&expected_signature);

        if (!std.mem.eql(u8, signature, &expected_signature)) {
            return AuthError.InvalidToken;
        }
    }

    pub fn generateToken(self: *Auth, subject: []const u8, expires_in: i64) ![]u8 {
        const now = std.time.timestamp();

        const header = TokenHeader{
            .alg = "HS256",
            .typ = "JWT",
        };

        const payload = TokenPayload{
            .sub = subject,
            .exp = now + expires_in,
            .iat = now,
        };

        var token = std.ArrayList(u8){};
        defer token.deinit(self.allocator);

        var adapter = token.writer(self.allocator).adaptToNewApi(&.{});
        const writer: *std.Io.Writer = &adapter.new_interface;

        // Simplified JWT creation
        try std.json.fmt(header, .{}).format(writer);
        try token.append(self.allocator, '.');
        try std.json.fmt(payload, .{}).format(writer);

        return token.toOwnedSlice(self.allocator);
    }
};

test "verifyToken rejects malformed tokens" {
    var auth = Auth.init(std.testing.allocator, "secret");
    try std.testing.expectError(AuthError.InvalidToken, auth.verifyToken(""));
    try std.testing.expectError(AuthError.InvalidToken, auth.verifyToken("abc"));
    try std.testing.expectError(AuthError.InvalidToken, auth.verifyToken("header.payload"));
}

test "generateToken payload fields are sensible" {
    var auth = Auth.init(std.testing.allocator, "key");
    const expires_in: i64 = 10;
    const tok = try auth.generateToken("alice", expires_in);
    defer std.testing.allocator.free(tok);

    var it = std.mem.splitAny(u8, tok, ".");
    _ = it.next(); // header json
    const payload_json_opt = it.next();
    try std.testing.expect(payload_json_opt != null);
    const payload_json = payload_json_opt.?;

    const Payload = struct {
        sub: []const u8,
        exp: i64,
        iat: i64,
    };
    const parsed = try std.json.parseFromSlice(Payload, std.testing.allocator, payload_json, .{});
    defer parsed.deinit();
    const payload = parsed.value;

    try std.testing.expectEqualStrings("alice", payload.sub);
    try std.testing.expectEqual(@as(i64, expires_in), payload.exp - payload.iat);
}

test "verifyToken accepts matching signature and rejects tampered signature" {
    var auth = Auth.init(std.testing.allocator, "supersecret");

    // Try a few different subjects to avoid '.' appearing inside the raw signature bytes
    var attempt: usize = 0;
    var verified_once = false;
    while (attempt < 32 and !verified_once) : (attempt += 1) {
        var sbuf: [32]u8 = undefined;
        const subject = if (attempt == 0)
            "user-123"
        else
            try std.fmt.bufPrint(&sbuf, "user-123-{d}", .{attempt});

        const tok = try auth.generateToken(subject, 3600);
        defer std.testing.allocator.free(tok);

        var it2 = std.mem.splitAny(u8, tok, ".");
        const header_json = it2.next().?;
        const payload_json = it2.next().?;

        var mac = crypto.auth.hmac.sha2.HmacSha256.init("supersecret");
        mac.update(header_json);
        mac.update(".");
        mac.update(payload_json);

        var sig: [crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
        mac.final(&sig);

        if (std.mem.indexOfScalar(u8, sig[0..], '.') != null) {
            // Signature contains '.', try another subject
            continue;
        }

        // Build token: header.payload.signature (signature is raw bytes per current verifyToken)
        const total_len = header_json.len + 1 + payload_json.len + 1 + sig.len;
        var full = try std.testing.allocator.alloc(u8, total_len);
        defer std.testing.allocator.free(full);
        var idx: usize = 0;
        std.mem.copyForwards(u8, full[idx .. idx + header_json.len], header_json);
        idx += header_json.len;
        full[idx] = '.';
        idx += 1;
        std.mem.copyForwards(u8, full[idx .. idx + payload_json.len], payload_json);
        idx += payload_json.len;
        full[idx] = '.';
        idx += 1;
        std.mem.copyForwards(u8, full[idx .. idx + sig.len], sig[0..]);
        idx += sig.len;

        // Should verify
        try auth.verifyToken(full);

        // Tamper last byte of signature and expect failure
        full[total_len - 1] ^= 0xFF;
        try std.testing.expectError(AuthError.InvalidToken, auth.verifyToken(full));

        verified_once = true;
    }

    // Ensure the test actually verified once
    try std.testing.expect(verified_once);
}
