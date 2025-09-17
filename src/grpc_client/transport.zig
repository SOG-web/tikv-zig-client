const std = @import("std");
const net = std.net;
const http2 = struct {
    pub const connection = @import("http2/connection.zig");
    pub const frame = @import("http2/frame.zig");
    pub const stream = @import("http2/stream.zig");
};
const hpack = @import("http2/hpack_compliant.zig");
const framing = @import("grpc/framing.zig");
const compression = @import("features/compression.zig");

fn percentDecodeString(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, s, '%') == null) return allocator.dupe(u8, s);
    var out = std.ArrayList(u8){};
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '%' and i + 2 < s.len) {
            const h1 = s[i + 1];
            const h2 = s[i + 2];
            const v = hexToByte(h1, h2) catch {
                try out.append(allocator, s[i]);
                continue;
            };
            try out.append(allocator, v);
            i += 2;
        } else {
            try out.append(allocator, s[i]);
        }
    }
    return out.toOwnedSlice(allocator);
}

fn hexToByte(h1: u8, h2: u8) !u8 {
    const v1 = std.fmt.charToDigit(h1, 16) catch return error.Invalid;
    const v2 = std.fmt.charToDigit(h2, 16) catch return error.Invalid;
    return @as(u8, @intCast((v1 * 16) + v2));
}

pub const TransportError = error{
    ConnectionClosed,
    InvalidHeader,
    PayloadTooLarge,
    CompressionNotSupported,
    Http2Error,
    GrpcStatus,
    Timeout,
};

pub const GrpcStatusInfo = struct {
    code: u32,
    message: []u8, // owned by Transport until taken
};

pub const Transport = struct {
    stream: net.Stream,
    read_buf: []u8,
    write_buf: []u8,
    allocator: std.mem.Allocator,
    http2_conn: ?http2.connection.Connection,
    last_status: ?GrpcStatusInfo = null,

    pub fn init(allocator: std.mem.Allocator, stream: net.Stream) !Transport {
        var transport = Transport{
            .stream = stream,
            .read_buf = try allocator.alloc(u8, 1024 * 64),
            .write_buf = try allocator.alloc(u8, 1024 * 64),
            .allocator = allocator,
            .http2_conn = null,
        };

        // Initialize HTTP/2 connection
        transport.http2_conn = try http2.connection.Connection.init(allocator);
        try transport.setupHttp2();

        return transport;
    }

    pub fn deinit(self: *Transport) void {
        if (self.http2_conn) |*conn| {
            conn.deinit();
        }
        if (self.last_status) |st| {
            self.allocator.free(st.message);
        }
        self.allocator.free(self.read_buf);
        self.allocator.free(self.write_buf);
        self.stream.close();
    }

    fn setupHttp2(self: *Transport) !void {
        // Send HTTP/2 connection preface
        _ = try self.stream.write(http2.connection.Connection.PREFACE);

        // Send initial SETTINGS frame
        var settings_frame = try http2.frame.Frame.init(self.allocator);
        defer settings_frame.deinit(self.allocator);

        settings_frame.type = .SETTINGS;
        settings_frame.flags = 0;
        settings_frame.stream_id = 0;
        // Add your settings here

        var buffered_writer = self.stream.writer(self.write_buf);
        const writer = &buffered_writer.interface;
        try settings_frame.encode(writer);
        try writer.flush();
    }

    pub fn readMessage(self: *Transport) ![]const u8 {
        var buffered_reader = self.stream.reader(&self.read_buf);
        const frame_reader = &buffered_reader.file_reader.interface;
        const frame = try http2.frame.Frame.decode(frame_reader, self.allocator);
        defer frame.deinit(self.allocator);

        if (frame.type == .DATA) {
            return try self.allocator.dupe(u8, frame.payload);
        }

        return TransportError.Http2Error;
    }

    pub fn writeMessage(self: *Transport, message: []const u8) !void {
        var data_frame = try http2.frame.Frame.init(self.allocator);
        defer data_frame.deinit(self.allocator);

        data_frame.type = .DATA;
        data_frame.flags = http2.frame.FrameFlags.END_STREAM;
        data_frame.stream_id = 1; // Use appropriate stream ID
        data_frame.payload = message;
        data_frame.length = @intCast(message.len);

        var buffered_writer = self.stream.writer(self.write_buf);
        const writer = &buffered_writer.interface;
        try data_frame.encode(writer);
        try writer.flush();
    }

    // Perform a full gRPC unary call on a fresh HTTP/2 stream.
    // - Builds minimal gRPC request HEADERS via HPACK
    // - Frames the protobuf payload with the 5-byte gRPC prefix (and optional compression)
    // - Sends DATA with END_STREAM
    // - Reads DATA frames for the response, then trailer HEADERS, validates grpc-status if decodable
    // Returns owned response message bytes (after deframing and decompression if needed)
    pub fn unary(
        self: *Transport,
        authority: []const u8,
        path: []const u8,
        payload: []const u8,
        alg: compression.Compression.Algorithm,
        auth_token: ?[]const u8,
        timeout_ms: ?u64,
    ) ![]u8 {
        const conn_ptr = &self.http2_conn.?;

        std.debug.print("Sending gRPC request - createStream\n", .{});
        // Create a new HTTP/2 stream id
        const s = try conn_ptr.createStream();
        const sid: u31 = s.id;

        std.debug.print("Sending gRPC request - createStream - sid: {d}\n", .{sid});

        // Build request headers as fixed pairs (avoid hashmap iterator issues)
        var pairs = std.ArrayList(hpack.Pair){};
        defer pairs.deinit(self.allocator);
        try pairs.append(self.allocator, .{ .name = ":method", .value = "POST" });
        try pairs.append(self.allocator, .{ .name = ":scheme", .value = "http" }); // TODO: TLS => "https"
        try pairs.append(self.allocator, .{ .name = ":authority", .value = authority });
        try pairs.append(self.allocator, .{ .name = ":path", .value = path });
        try pairs.append(self.allocator, .{ .name = "content-type", .value = "application/grpc+proto" });
        try pairs.append(self.allocator, .{ .name = "te", .value = "trailers" });
        if (auth_token) |tok| {
            try pairs.append(self.allocator, .{ .name = "authorization", .value = tok });
        }
        var timeout_hdr_owned: ?[]u8 = null;
        defer if (timeout_hdr_owned) |h| self.allocator.free(h);
        if (timeout_ms) |ms| {
            // gRPC timeout header uses a number + unit. We'll use milliseconds (m)
            var buf: [32]u8 = undefined;
            const slice = try std.fmt.bufPrint(buf[0..], "{d}m", .{ms});
            const hdr = try self.allocator.dupe(u8, slice);
            timeout_hdr_owned = hdr; // ensure lifetime until function exit
            try pairs.append(self.allocator, .{ .name = "grpc-timeout", .value = hdr });

            std.debug.print("Sending gRPC request - set grpc-timeout: {s}\n", .{slice});
        }
        switch (alg) {
            .none => {},
            .gzip => try pairs.append(self.allocator, .{ .name = "grpc-encoding", .value = "gzip" }),
            .deflate => try pairs.append(self.allocator, .{ .name = "grpc-encoding", .value = "deflate" }),
        }
        // Optionally advertise accept-encoding
        try pairs.append(self.allocator, .{ .name = "grpc-accept-encoding", .value = "gzip,deflate" });

        // HPACK encode
        const encoded_headers = try conn_ptr.encoder.encodePairs(pairs.items);

        std.debug.print("Sending gRPC request - encoded headers: {s}\n", .{encoded_headers});

        // Send HEADERS frame
        var headers_frame = try http2.frame.Frame.init(self.allocator);
        defer headers_frame.deinit(self.allocator);
        headers_frame.type = .HEADERS;
        headers_frame.flags = http2.frame.FrameFlags.END_HEADERS;
        headers_frame.stream_id = sid;
        headers_frame.payload = encoded_headers;
        headers_frame.length = @intCast(encoded_headers.len);

        {
            var bw = self.stream.writer(self.write_buf);
            const w = &bw.interface;
            try headers_frame.encode(w);
            try w.flush();
        }

        // Compress payload at message level if requested
        var compressed_alloc: ?[]u8 = null;
        var compressed_payload: []const u8 = undefined;
        var use_compression = false;
        switch (alg) {
            .none => {
                compressed_payload = payload;
                use_compression = false;
            },
            .gzip => {
                var comp = compression.Compression.init(self.allocator);
                const tmp = try comp.compress(payload, .gzip);
                compressed_alloc = tmp;
                compressed_payload = tmp;
                use_compression = true;
            },
            .deflate => {
                var comp = compression.Compression.init(self.allocator);
                const tmp = try comp.compress(payload, .deflate);
                compressed_alloc = tmp;
                compressed_payload = tmp;
                use_compression = true;
            },
        }
        defer if (compressed_alloc) |buf| self.allocator.free(buf);

        const framed = try framing.frameMessage(self.allocator, compressed_payload, use_compression);

        // Send DATA with END_STREAM
        var data_frame = try http2.frame.Frame.init(self.allocator);
        defer data_frame.deinit(self.allocator);
        data_frame.type = .DATA;
        data_frame.flags = http2.frame.FrameFlags.END_STREAM;
        data_frame.stream_id = sid;
        data_frame.payload = framed;
        data_frame.length = @intCast(framed.len);
        {
            var bw2 = self.stream.writer(self.write_buf);
            const w2 = &bw2.interface;
            try data_frame.encode(w2);
            try w2.flush();
        }

        // Read response frames for this stream
        var response_bytes = std.ArrayList(u8){};
        defer response_bytes.deinit(self.allocator);
        var saw_trailers = false;
        var saw_initial_headers = false;
        var initial_content_type_ok = false;
        var initial_status_ok = false;
        var resp_grpc_encoding: ?[]u8 = null; // owned copy from response HEADERS
        defer if (resp_grpc_encoding) |enc| self.allocator.free(enc);
        var status_ok = true;
        var status_code_val: u32 = 0;
        var status_message_buf: ?[]u8 = null;
        defer if (status_message_buf) |m| self.allocator.free(m);
        const begin_ns = std.time.nanoTimestamp();
        const deadline_ns: ?i128 = if (timeout_ms) |ms| @as(i128, @intCast(ms)) * 1_000_000 else null;
        var br = self.stream.reader(self.read_buf);
        const r = &br.file_reader.interface;
        while (true) {
            if (deadline_ns) |dl| {
                const now = std.time.nanoTimestamp();
                if (now - begin_ns > dl) {
                    return TransportError.Timeout;
                }
            }
            var f = try http2.frame.Frame.decode(r, self.allocator);
            defer f.deinit(self.allocator);

            if (f.stream_id != sid) {
                // For simplicity, ignore frames not belonging to our stream in this prototype
                continue;
            }

            switch (f.type) {
                .DATA => {
                    try response_bytes.appendSlice(self.allocator, f.payload);
                },
                .HEADERS => {
                    // Attempt to HPACK-decode headers; if it fails, still allow success path
                    const decode_result = conn_ptr.decoder.decode(f.payload) catch null;
                    if (decode_result) |hdrs_val| {
                        var hdrs = hdrs_val; // make mutable copy for iterator and deinit
                        defer conn_ptr.decoder.freeDecodedHeaders(&hdrs);
                        // If this is non-trailing HEADERS (no END_STREAM), validate and capture response metadata
                        if ((f.flags & http2.frame.FrameFlags.END_STREAM) == 0) {
                            saw_initial_headers = true;
                            if (hdrs.get(":status")) |st| {
                                initial_status_ok = std.mem.eql(u8, st, "200");
                            }
                            if (hdrs.get("content-type")) |ct| {
                                // accept application/grpc or application/grpc+proto
                                initial_content_type_ok = std.mem.startsWith(u8, ct, "application/grpc");
                            }
                            if (hdrs.get("grpc-encoding")) |enc| {
                                if (resp_grpc_encoding == null) {
                                    resp_grpc_encoding = self.allocator.dupe(u8, enc) catch null;
                                }
                            }
                        } else {
                            // Trailers: extract grpc-status and grpc-message
                            if (hdrs.get("grpc-status")) |st| {
                                // status "0" == OK
                                status_ok = std.mem.eql(u8, st, "0");
                                // attempt parse numeric code
                                status_code_val = std.fmt.parseInt(u32, st, 10) catch 2; // arbitrary non-zero on parse error
                            } else {
                                status_ok = false;
                                status_code_val = 2; // Unknown
                            }
                            if (hdrs.get("grpc-message")) |m| {
                                status_message_buf = percentDecodeString(self.allocator, m) catch null;
                            }
                        }
                    }
                    if ((f.flags & http2.frame.FrameFlags.END_STREAM) != 0) {
                        saw_trailers = true;
                        if (!status_ok) {
                            // Save last status info for retrieval and return error
                            var msg_copy: []u8 = &[_]u8{};
                            if (status_message_buf) |m| {
                                msg_copy = self.allocator.dupe(u8, m) catch &[_]u8{};
                            } else {
                                // allocate empty owned slice to unify ownership
                                msg_copy = self.allocator.alloc(u8, 0) catch &[_]u8{};
                            }
                            if (self.last_status) |st| {
                                self.allocator.free(st.message);
                            }
                            self.last_status = .{ .code = status_code_val, .message = msg_copy };
                            return TransportError.GrpcStatus;
                        }
                        break;
                    }
                },
                else => {},
            }

            if (saw_trailers) break;
        }

        // Validate initial headers if present
        if (saw_initial_headers and !(initial_status_ok and initial_content_type_ok)) {
            return TransportError.InvalidHeader;
        }

        const all = try response_bytes.toOwnedSlice(self.allocator);
        defer self.allocator.free(all);

        // Deframe gRPC and possibly decompress
        const def = try framing.deframeMessage(self.allocator, all);
        defer self.allocator.free(def.message);

        if (def.compressed) {
            // Prefer the response-declared algorithm if present; otherwise fallback to request alg
            var used_alg: compression.Compression.Algorithm = .none;
            if (resp_grpc_encoding) |enc| {
                if (std.mem.eql(u8, enc, "gzip")) {
                    used_alg = .gzip;
                } else if (std.mem.eql(u8, enc, "deflate")) {
                    used_alg = .deflate;
                } else {
                    return TransportError.CompressionNotSupported;
                }
            } else {
                used_alg = alg;
            }
            if (used_alg == .none) return TransportError.CompressionNotSupported;
            var comp = compression.Compression.init(self.allocator);
            return try comp.decompress(def.message, used_alg);
        } else {
            return self.allocator.dupe(u8, def.message);
        }
    }

    // Helper for testing - encodes a frame directly to a buffer
    pub fn encodeFrameToBuffer(frame: http2.frame.Frame, buffer: []u8) ![]u8 {
        var fbs = std.io.Writer.fixed(buffer);
        try frame.encode(&fbs);
        return fbs.buffered();
    }

    /// If the previous unary call returned TransportError.GrpcStatus,
    /// callers can retrieve structured status information here.
    /// Ownership of the message is transferred to the caller.
    pub fn takeLastGrpcStatus(self: *Transport) ?GrpcStatusInfo {
        const st = self.last_status;
        self.last_status = null;
        return st;
    }
};
