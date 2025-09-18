// Integration layer that uses the existing HTTP/2 implementation with TLS support
const std = @import("std");
const tls = @import("tls.zig");
const connection = @import("http2/connection.zig");
const frame = @import("http2/frame.zig");
const hpack = @import("http2/hpack_compliant.zig");
const stream = @import("http2/stream.zig");

pub const Http2TlsConnection = struct {
    allocator: std.mem.Allocator,
    socket: std.posix.socket_t,
    tls_connection: ?*tls.TlsConnection,
    http2_connection: connection.Connection,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16, use_tls: bool, tls_config: ?tls.TlsConfig) !Self {
        // Create socket
        const socket = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0);
        errdefer std.posix.close(socket);

        // Connect to server
        var addr = std.net.Address.parseIp4(host, port) catch
            try std.net.Address.resolveIp(host, port, std.posix.AF.INET);

        try std.posix.connect(socket, &addr.any, addr.getOsSockLen());

        var tls_conn: ?*tls.TlsConnection = null;
        if (use_tls) {
            const config = tls_config orelse tls.TlsConfig{
                .server_name = host,
                .alpn_protocols = &.{"h2"},
            };

            tls_conn = try allocator.create(tls.TlsConnection);
            tls_conn.?.* = try tls.TlsConnection.init(allocator, socket, config);

            // Verify HTTP/2 was negotiated
            if (!tls_conn.?.isHttp2()) {
                std.log.warn("HTTP/2 not negotiated via ALPN, falling back", .{});
            }
        }

        // Initialize HTTP/2 connection using existing implementation
        const http2_conn = try connection.Connection.init(allocator);

        var self = Self{
            .allocator = allocator,
            .socket = socket,
            .tls_connection = tls_conn,
            .http2_connection = http2_conn,
        };

        // Send connection preface
        try self.sendConnectionPreface();

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.tls_connection) |tls_conn| {
            tls_conn.deinit();
            self.allocator.destroy(tls_conn);
        }
        std.posix.close(self.socket);
        self.http2_connection.deinit();
    }

    fn sendConnectionPreface(self: *Self) !void {
        // Send HTTP/2 connection preface
        try self.writeAll(connection.Connection.PREFACE);

        // Send initial SETTINGS frame using existing frame implementation
        var settings_frame = try frame.Frame.init(self.allocator);
        defer settings_frame.deinit(self.allocator);

        settings_frame.type = .SETTINGS;
        settings_frame.flags = 0;
        settings_frame.stream_id = 0;

        // Build settings payload
        var settings_payload = std.ArrayList(u8){};
        defer settings_payload.deinit(self.allocator);

        // SETTINGS_ENABLE_PUSH = 0
        var setting_bytes: [6]u8 = undefined;
        std.mem.writeInt(u16, setting_bytes[0..2], 0x2, .big); // ENABLE_PUSH
        std.mem.writeInt(u32, setting_bytes[2..6], 0, .big);
        try settings_payload.appendSlice(self.allocator, &setting_bytes);

        // SETTINGS_MAX_CONCURRENT_STREAMS = 100
        std.mem.writeInt(u16, setting_bytes[0..2], 0x3, .big); // MAX_CONCURRENT_STREAMS
        std.mem.writeInt(u32, setting_bytes[2..6], 100, .big);
        try settings_payload.appendSlice(self.allocator, &setting_bytes);

        settings_frame.payload = try settings_payload.toOwnedSlice(self.allocator);
        settings_frame.length = @intCast(settings_frame.payload.len);

        try self.sendFrame(settings_frame);
    }

    pub fn createStream(self: *Self) !*stream.Stream {
        return self.http2_connection.createStream();
    }

    pub fn sendHeaders(self: *Self, stream_id: u31, headers: std.StringHashMap([]const u8)) !void {
        return self.http2_connection.sendHeaders(stream_id, headers);
    }

    pub fn sendFrame(self: *Self, f: frame.Frame) !void {
        const encoded = try f.encode(self.allocator);
        defer self.allocator.free(encoded);
        try self.writeAll(encoded);
    }

    pub fn receiveFrame(self: *Self) !frame.Frame {
        // Read frame header (9 bytes)
        var header: [9]u8 = undefined;
        try self.readAll(&header);

        const length = std.mem.readInt(u24, header[0..3], .big);
        const frame_type: frame.FrameType = @enumFromInt(header[3]);
        const flags = header[4];
        const stream_id = std.mem.readInt(u32, header[5..9], .big) & 0x7FFFFFFF;

        // Read payload
        const payload = try self.allocator.alloc(u8, length);
        if (length > 0) {
            try self.readAll(payload);
        }

        var f = try frame.Frame.init(self.allocator);
        f.type = frame_type;
        f.flags = flags;
        f.stream_id = @intCast(stream_id);
        f.payload = payload;
        f.length = @intCast(length);

        return f;
    }

    fn writeAll(self: *Self, data: []const u8) !void {
        if (self.tls_connection) |tls_conn| {
            try tls_conn.writeAll(data);
        } else {
            var written: usize = 0;
            while (written < data.len) {
                const n = try std.posix.write(self.socket, data[written..]);
                written += n;
            }
        }
    }

    fn readAll(self: *Self, buffer: []u8) !void {
        if (self.tls_connection) |tls_conn| {
            try tls_conn.readAll(buffer);
        } else {
            var read_bytes: usize = 0;
            while (read_bytes < buffer.len) {
                const n = try std.posix.read(self.socket, buffer[read_bytes..]);
                if (n == 0) return error.ConnectionClosed;
                read_bytes += n;
            }
        }
    }

    // Convenience method to create gRPC headers
    pub fn createGrpcHeaders(allocator: std.mem.Allocator, method_path: []const u8, authority: []const u8) !std.StringHashMap([]const u8) {
        var headers = std.StringHashMap([]const u8).init(allocator);

        try headers.put(":method", "POST");
        try headers.put(":scheme", "https");
        try headers.put(":authority", authority);
        try headers.put(":path", method_path);
        try headers.put("content-type", "application/grpc+proto");
        try headers.put("te", "trailers");
        try headers.put("grpc-encoding", "gzip");
        try headers.put("grpc-accept-encoding", "gzip");
        try headers.put("user-agent", "tikv-client-zig/1.0");

        return headers;
    }
};

test "http2 tls integration" {
    const allocator = std.testing.allocator;

    // Test gRPC headers creation
    var headers = try Http2TlsConnection.createGrpcHeaders(allocator, "/pdpb.PD/GetRegion", "pd.example.com:2379");
    defer headers.deinit();

    try std.testing.expect(headers.count() == 9);
    try std.testing.expect(std.mem.eql(u8, headers.get(":method").?, "POST"));
    try std.testing.expect(std.mem.eql(u8, headers.get("content-type").?, "application/grpc+proto"));
}
