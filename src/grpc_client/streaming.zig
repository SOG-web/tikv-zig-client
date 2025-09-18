// Streaming gRPC support for bidirectional and server-side streaming
const std = @import("std");
const http2_integration = @import("http2_integration.zig");
const connection = @import("http2/connection.zig");
const frame = @import("http2/frame.zig");
const stream_mod = @import("http2/stream.zig");
const tls = @import("tls.zig");

// Simple header struct for gRPC
pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const StreamError = error{
    StreamClosed,
    InvalidFrame,
    FlowControlViolation,
    ProtocolError,
    OutOfMemory,
    ConnectionError,
};

pub const StreamType = enum {
    unary,
    client_streaming,
    server_streaming,
    bidirectional_streaming,
};

pub const StreamState = enum {
    idle,
    open,
    half_closed_local,
    half_closed_remote,
    closed,
};

/// Represents a gRPC stream for streaming RPCs
pub const GrpcStream = struct {
    stream_id: u32,
    stream_type: StreamType,
    state: StreamState,
    connection: *http2_integration.Http2TlsConnection,
    allocator: std.mem.Allocator,

    // Flow control
    local_window: i32,
    remote_window: i32,

    // Buffering
    incoming_frames: std.ArrayList(frame.Frame),
    outgoing_queue: std.ArrayList([]const u8),

    // Metadata
    headers_sent: bool,
    headers_received: bool,
    trailers_received: bool,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        stream_id: u32,
        stream_type: StreamType,
        http2_connection: *http2_integration.Http2TlsConnection,
    ) !Self {
        return Self{
            .stream_id = stream_id,
            .stream_type = stream_type,
            .state = .idle,
            .connection = http2_connection,
            .allocator = allocator,
            .local_window = 65535, // Default HTTP/2 window size
            .remote_window = 65535,
            .incoming_frames = std.ArrayList(frame.Frame){},
            .outgoing_queue = std.ArrayList([]const u8){},
            .headers_sent = false,
            .headers_received = false,
            .trailers_received = false,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.incoming_frames.items) |fr| {
            fr.deinit(self.allocator);
        }
        self.incoming_frames.deinit();

        for (self.outgoing_queue.items) |data| {
            self.allocator.free(data);
        }
        self.outgoing_queue.deinit();
    }

    /// Send initial headers for the stream
    pub fn sendHeaders(self: *Self, headers: []const Header) !void {
        if (self.headers_sent) return StreamError.ProtocolError;

        // Convert headers to StringHashMap for existing HTTP/2 connection
        var header_map = std.StringHashMap([]const u8).init(self.allocator);
        defer header_map.deinit();

        for (headers) |hdr| {
            try header_map.put(hdr.name, hdr.value);
        }

        try self.connection.sendHeaders(@intCast(self.stream_id), header_map);
        self.headers_sent = true;
        self.state = .open;
    }

    /// Send data frame
    pub fn sendData(self: *Self, data: []const u8, end_stream: bool) !void {
        if (self.state == .closed or self.state == .half_closed_local) {
            return StreamError.StreamClosed;
        }

        // Check flow control
        if (@as(i32, @intCast(data.len)) > self.remote_window) {
            return StreamError.FlowControlViolation;
        }

        // Create DATA frame using existing frame implementation
        var data_frame = try frame.Frame.init(self.allocator);
        defer data_frame.deinit(self.allocator);

        data_frame.type = .DATA;
        data_frame.stream_id = @intCast(self.stream_id);
        if (end_stream) {
            data_frame.flags = frame.FrameFlags.END_STREAM;
        }
        data_frame.payload = try self.allocator.dupe(u8, data);
        data_frame.length = @intCast(data_frame.payload.len);

        try self.connection.sendFrame(data_frame);
        self.remote_window -= @intCast(data.len);

        if (end_stream) {
            self.state = switch (self.state) {
                .open => .half_closed_local,
                .half_closed_remote => .closed,
                else => self.state,
            };
        }
    }

    /// Send end of stream (half-close local side)
    pub fn sendEndStream(self: *Self) !void {
        try self.sendData(&.{}, true);
    }

    /// Send trailers (implies end of stream)
    pub fn sendTrailers(self: *Self, trailers: []const Header) !void {
        // Convert trailers to StringHashMap
        var trailer_map = std.StringHashMap([]const u8).init(self.allocator);
        defer trailer_map.deinit();

        for (trailers) |tr| {
            try trailer_map.put(tr.name, tr.value);
        }

        try self.connection.sendHeaders(@intCast(self.stream_id), trailer_map);
        self.state = switch (self.state) {
            .open => .half_closed_local,
            .half_closed_remote => .closed,
            else => self.state,
        };
    }

    /// Receive next message from the stream
    pub fn receiveMessage(self: *Self) !?[]u8 {
        while (true) {
            // Process any pending frames
            if (self.incoming_frames.items.len > 0) {
                const f = self.incoming_frames.orderedRemove(0);
                defer f.deinit(self.allocator);

                switch (f.type) {
                    .HEADERS => {
                        if (!self.headers_received) {
                            self.headers_received = true;
                            // Process headers but continue to look for data
                            continue;
                        } else {
                            // These are trailers
                            self.trailers_received = true;
                            if (f.flags.END_STREAM) {
                                self.state = switch (self.state) {
                                    .open => .half_closed_remote,
                                    .half_closed_local => .closed,
                                    else => self.state,
                                };
                                return null; // End of stream
                            }
                        }
                    },
                    .DATA => {
                        // Update flow control
                        self.local_window -= @intCast(f.payload.len);

                        // Send window update if needed
                        if (self.local_window < 32768) {
                            try self.sendWindowUpdate(65535 - self.local_window);
                            self.local_window = 65535;
                        }

                        if (f.flags.END_STREAM) {
                            self.state = switch (self.state) {
                                .open => .half_closed_remote,
                                .half_closed_local => .closed,
                                else => self.state,
                            };
                        }

                        if (f.payload.len > 0) {
                            return try self.allocator.dupe(u8, f.payload);
                        }

                        if (f.flags.END_STREAM) {
                            return null; // End of stream
                        }
                    },
                    .WINDOW_UPDATE => {
                        const increment = std.mem.readInt(u32, f.payload[0..4], .big);
                        self.remote_window += @intCast(increment);
                    },
                    .RST_STREAM => {
                        self.state = .closed;
                        return StreamError.StreamClosed;
                    },
                    else => {
                        // Ignore other frame types
                        continue;
                    },
                }
            }

            // Wait for more frames from connection
            const f = try self.connection.receiveFrame();
            if (f.stream_id == self.stream_id) {
                try self.incoming_frames.append(f);
            } else {
                // Frame for different stream, let connection handle it
                try self.connection.handleFrame(f);
            }
        }
    }

    /// Send window update frame
    fn sendWindowUpdate(self: *Self, increment: u32) !void {
        var payload: [4]u8 = undefined;
        std.mem.writeInt(u32, &payload, increment, .big);

        var window_frame = try frame.Frame.init(self.allocator);
        defer window_frame.deinit(self.allocator);

        window_frame.type = .WINDOW_UPDATE;
        window_frame.flags = 0;
        window_frame.stream_id = @intCast(self.stream_id);
        window_frame.payload = try self.allocator.dupe(u8, &payload);
        window_frame.length = @intCast(window_frame.payload.len);

        try self.connection.sendFrame(window_frame);
    }

    /// Reset the stream
    pub fn reset(self: *Self, error_code: u32) !void {
        var payload: [4]u8 = undefined;
        std.mem.writeInt(u32, &payload, error_code, .big);

        var rst_frame = try frame.Frame.init(self.allocator);
        defer rst_frame.deinit(self.allocator);

        rst_frame.type = .RST_STREAM;
        rst_frame.flags = 0;
        rst_frame.stream_id = @intCast(self.stream_id);
        rst_frame.payload = try self.allocator.dupe(u8, &payload);
        rst_frame.length = @intCast(rst_frame.payload.len);

        try self.connection.sendFrame(rst_frame);
        self.state = .closed;
    }

    /// Check if stream is closed
    pub fn isClosed(self: *Self) bool {
        return self.state == .closed;
    }

    /// Check if stream can send data
    pub fn canSend(self: *Self) bool {
        return self.state == .open or self.state == .half_closed_remote;
    }

    /// Check if stream can receive data
    pub fn canReceive(self: *Self) bool {
        return self.state == .open or self.state == .half_closed_local;
    }
};

/// Streaming gRPC client for handling multiple concurrent streams
pub const StreamingGrpcClient = struct {
    connection: *http2_integration.Http2TlsConnection,
    allocator: std.mem.Allocator,
    streams: std.HashMap(u32, *GrpcStream),
    next_stream_id: u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, con: *http2_integration.Http2TlsConnection) Self {
        return Self{
            .connection = con,
            .allocator = allocator,
            .streams = std.HashMap(u32, *GrpcStream).init(allocator),
            .next_stream_id = 1, // Client-initiated streams are odd
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.streams.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.streams.deinit();
    }

    /// Create a new stream
    pub fn createStream(self: *Self, stream_type: StreamType) !*GrpcStream {
        const stream_id = self.next_stream_id;
        self.next_stream_id += 2; // Skip even numbers (server-initiated)

        const stream = try self.allocator.create(GrpcStream);
        stream.* = try GrpcStream.init(self.allocator, stream_id, stream_type, self.connection);

        try self.streams.put(stream_id, stream);
        return stream;
    }

    /// Remove and cleanup a stream
    pub fn removeStream(self: *Self, stream_id: u32) void {
        if (self.streams.fetchRemove(stream_id)) |entry| {
            entry.value.deinit();
            self.allocator.destroy(entry.value);
        }
    }

    /// Get stream by ID
    pub fn getStream(self: *Self, stream_id: u32) ?*GrpcStream {
        return self.streams.get(stream_id);
    }

    /// Process incoming frames and route to appropriate streams
    pub fn processIncomingFrames(self: *Self) !void {
        while (true) {
            const f = self.connection.receiveFrame() catch |err| switch (err) {
                error.WouldBlock => return,
                else => return err,
            };

            if (f.stream_id == 0) {
                // Connection-level frame
                try self.connection.handleFrame(f);
            } else {
                // Stream-level frame
                if (self.getStream(@intCast(f.stream_id))) |stream| {
                    try stream.incoming_frames.append(f);
                } else {
                    // Unknown stream, send RST_STREAM
                    try self.sendRstStream(@intCast(f.stream_id), 8); // CANCEL error code
                    f.deinit(self.allocator);
                }
            }
        }
    }

    fn sendRstStream(self: *Self, stream_id: u32, error_code: u32) !void {
        var payload: [4]u8 = undefined;
        std.mem.writeInt(u32, &payload, error_code, .big);

        var rst_frame = try frame.Frame.init(self.allocator);
        defer rst_frame.deinit(self.allocator);

        rst_frame.type = .RST_STREAM;
        rst_frame.flags = 0;
        rst_frame.stream_id = @intCast(stream_id);
        rst_frame.payload = try self.allocator.dupe(u8, &payload);
        rst_frame.length = @intCast(rst_frame.payload.len);

        try self.connection.sendFrame(rst_frame);
    }
};

test "grpc stream creation" {
    const allocator = std.testing.allocator;

    // Mock connection for testing
    var mock_connection = connection.Connection{
        .allocator = allocator,
        .next_stream_id = 1,
        .streams = std.AutoHashMap(u31, stream_mod.Stream).init(allocator),
        .encoder = undefined, // Would need proper HPACK encoder
        .decoder = undefined, // Would need proper HPACK decoder
    };
    defer mock_connection.streams.deinit();

    var stream = try GrpcStream.init(allocator, 1, .bidirectional_streaming, @ptrCast(&mock_connection));
    defer stream.deinit();

    try std.testing.expect(stream.stream_id == 1);
    try std.testing.expect(stream.stream_type == .bidirectional_streaming);
    try std.testing.expect(stream.state == .idle);
}
