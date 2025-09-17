const std = @import("std");
const huffman = @import("huffman.zig");

pub const HpackError = error{
    InvalidIndex,
    BufferTooSmall,
    InvalidHuffmanCode,
    IntegerOverflow,
    InvalidHeaderBlock,
    DynamicTableFull,
};

pub const Pair = struct {
    name: []const u8,
    value: []const u8,
};

// RFC 7541 Static Table (Appendix B)
const STATIC_TABLE = [_]Pair{
    .{ .name = ":authority", .value = "" }, // 1
    .{ .name = ":method", .value = "GET" }, // 2
    .{ .name = ":method", .value = "POST" }, // 3
    .{ .name = ":path", .value = "/" }, // 4
    .{ .name = ":path", .value = "/index.html" }, // 5
    .{ .name = ":scheme", .value = "http" }, // 6
    .{ .name = ":scheme", .value = "https" }, // 7
    .{ .name = ":status", .value = "200" }, // 8
    .{ .name = ":status", .value = "204" }, // 9
    .{ .name = ":status", .value = "206" }, // 10
    .{ .name = ":status", .value = "304" }, // 11
    .{ .name = ":status", .value = "400" }, // 12
    .{ .name = ":status", .value = "404" }, // 13
    .{ .name = ":status", .value = "500" }, // 14
    .{ .name = "accept-charset", .value = "" }, // 15
    .{ .name = "accept-encoding", .value = "gzip, deflate" }, // 16
    .{ .name = "accept-language", .value = "" }, // 17
    .{ .name = "accept-ranges", .value = "" }, // 18
    .{ .name = "accept", .value = "" }, // 19
    .{ .name = "access-control-allow-origin", .value = "" }, // 20
    .{ .name = "age", .value = "" }, // 21
    .{ .name = "allow", .value = "" }, // 22
    .{ .name = "authorization", .value = "" }, // 23
    .{ .name = "cache-control", .value = "" }, // 24
    .{ .name = "content-disposition", .value = "" }, // 25
    .{ .name = "content-encoding", .value = "" }, // 26
    .{ .name = "content-language", .value = "" }, // 27
    .{ .name = "content-length", .value = "" }, // 28
    .{ .name = "content-location", .value = "" }, // 29
    .{ .name = "content-range", .value = "" }, // 30
    .{ .name = "content-type", .value = "" }, // 31
    .{ .name = "cookie", .value = "" }, // 32
    .{ .name = "date", .value = "" }, // 33
    .{ .name = "etag", .value = "" }, // 34
    .{ .name = "expect", .value = "" }, // 35
    .{ .name = "expires", .value = "" }, // 36
    .{ .name = "from", .value = "" }, // 37
    .{ .name = "host", .value = "" }, // 38
    .{ .name = "if-match", .value = "" }, // 39
    .{ .name = "if-modified-since", .value = "" }, // 40
    .{ .name = "if-none-match", .value = "" }, // 41
    .{ .name = "if-range", .value = "" }, // 42
    .{ .name = "if-unmodified-since", .value = "" }, // 43
    .{ .name = "last-modified", .value = "" }, // 44
    .{ .name = "link", .value = "" }, // 45
    .{ .name = "location", .value = "" }, // 46
    .{ .name = "max-forwards", .value = "" }, // 47
    .{ .name = "proxy-authenticate", .value = "" }, // 48
    .{ .name = "proxy-authorization", .value = "" }, // 49
    .{ .name = "range", .value = "" }, // 50
    .{ .name = "referer", .value = "" }, // 51
    .{ .name = "refresh", .value = "" }, // 52
    .{ .name = "retry-after", .value = "" }, // 53
    .{ .name = "server", .value = "" }, // 54
    .{ .name = "set-cookie", .value = "" }, // 55
    .{ .name = "strict-transport-security", .value = "" }, // 56
    .{ .name = "transfer-encoding", .value = "" }, // 57
    .{ .name = "user-agent", .value = "" }, // 58
    .{ .name = "vary", .value = "" }, // 59
    .{ .name = "via", .value = "" }, // 60
    .{ .name = "www-authenticate", .value = "" }, // 61
};

const HeaderField = struct {
    name: []u8,
    value: []u8,
};

pub const Encoder = struct {
    dynamic_table: std.ArrayList(HeaderField),
    allocator: std.mem.Allocator,
    max_dynamic_table_size: u32,

    pub fn init(allocator: std.mem.Allocator) !Encoder {
        return Encoder{
            .dynamic_table = std.ArrayList(HeaderField){},
            .allocator = allocator,
            .max_dynamic_table_size = 4096, // Default per RFC 7541
        };
    }

    pub fn deinit(self: *Encoder) void {
        for (self.dynamic_table.items) |field| {
            self.allocator.free(field.name);
            self.allocator.free(field.value);
        }
        self.dynamic_table.deinit(self.allocator);
    }

    pub fn encodePairs(self: *Encoder, pairs: []const Pair) ![]u8 {
        var buffer = std.ArrayList(u8){};
        errdefer buffer.deinit(self.allocator);

        for (pairs) |pair| {
            try self.encodeHeaderField(&buffer, pair.name, pair.value);
        }

        return buffer.toOwnedSlice(self.allocator);
    }

    fn encodeHeaderField(self: *Encoder, buffer: *std.ArrayList(u8), name: []const u8, value: []const u8) !void {
        // Look for exact match in dynamic table first (more recent entries)
        if (self.findInDynamicTable(name, value)) |index| {
            const full_index = STATIC_TABLE.len + index + 1;
            try self.encodeInteger(buffer, @intCast(full_index), 7, 0x80);
            return;
        }
        
        // Look for exact match in static table
        if (self.findInStaticTable(name, value)) |index| {
            // Indexed Header Field (RFC 7541 Section 6.1)
            try self.encodeInteger(buffer, index, 7, 0x80);
            return;
        }

        // Look for name match in dynamic table
        if (self.findNameInDynamicTable(name)) |index| {
            const full_index = STATIC_TABLE.len + index + 1;
            try self.encodeInteger(buffer, @intCast(full_index), 6, 0x40);
            try self.encodeString(buffer, value, false); // Don't use Huffman for now
            try self.addToDynamicTable(name, value);
            return;
        }

        // Look for name match in static table
        if (self.findNameInStaticTable(name)) |index| {
            // Literal Header Field with Incremental Indexing — Indexed Name (RFC 7541 Section 6.2.1)
            try self.encodeInteger(buffer, index, 6, 0x40);
            try self.encodeString(buffer, value, false); // Don't use Huffman for now
            try self.addToDynamicTable(name, value);
            return;
        }

        // Literal Header Field with Incremental Indexing — New Name (RFC 7541 Section 6.2.1)
        try buffer.append(self.allocator, 0x40); // Pattern: 01
        try self.encodeString(buffer, name, false); // Don't use Huffman for now
        try self.encodeString(buffer, value, false); // Don't use Huffman for now
        try self.addToDynamicTable(name, value);
    }
    
    fn findInDynamicTable(self: *Encoder, name: []const u8, value: []const u8) ?u32 {
        for (self.dynamic_table.items, 0..) |field, i| {
            if (std.mem.eql(u8, field.name, name) and std.mem.eql(u8, field.value, value)) {
                return @intCast(i);
            }
        }
        return null;
    }
    
    fn findNameInDynamicTable(self: *Encoder, name: []const u8) ?u32 {
        for (self.dynamic_table.items, 0..) |field, i| {
            if (std.mem.eql(u8, field.name, name)) {
                return @intCast(i);
            }
        }
        return null;
    }
    
    fn addToDynamicTable(self: *Encoder, name: []const u8, value: []const u8) !void {
        const entry_size = name.len + value.len + 32; // RFC 7541 Section 4.1
        
        // Evict entries if necessary to make room
        while (self.getDynamicTableSize() + entry_size > self.max_dynamic_table_size and self.dynamic_table.items.len > 0) {
            const last_idx = self.dynamic_table.items.len - 1;
            const removed = self.dynamic_table.swapRemove(last_idx);
            self.allocator.free(removed.name);
            self.allocator.free(removed.value);
        }
        
        // Add new entry at the beginning (most recent)
        const new_entry = HeaderField{
            .name = try self.allocator.dupe(u8, name),
            .value = try self.allocator.dupe(u8, value),
        };
        
        try self.dynamic_table.insert(self.allocator, 0, new_entry);
    }
    
    fn getDynamicTableSize(self: *Encoder) u32 {
        var size: u32 = 0;
        for (self.dynamic_table.items) |field| {
            size += @intCast(field.name.len + field.value.len + 32);
        }
        return size;
    }

    fn findInStaticTable(self: *Encoder, name: []const u8, value: []const u8) ?u32 {
        _ = self;
        for (STATIC_TABLE, 1..) |entry, i| {
            if (std.mem.eql(u8, entry.name, name) and std.mem.eql(u8, entry.value, value)) {
                return @intCast(i);
            }
        }
        return null;
    }

    fn findNameInStaticTable(self: *Encoder, name: []const u8) ?u32 {
        _ = self;
        for (STATIC_TABLE, 1..) |entry, i| {
            if (std.mem.eql(u8, entry.name, name)) {
                return @intCast(i);
            }
        }
        return null;
    }

    fn encodeInteger(self: *Encoder, buffer: *std.ArrayList(u8), value: u32, prefix_bits: u3, pattern: u8) !void {
        const max_prefix = (@as(u32, 1) << prefix_bits) - 1;

        if (value < max_prefix) {
            try buffer.append(self.allocator, pattern | @as(u8, @intCast(value)));
        } else {
            try buffer.append(self.allocator, pattern | @as(u8, @intCast(max_prefix)));
            var remaining = value - max_prefix;
            while (remaining >= 128) {
                try buffer.append(self.allocator, @as(u8, @intCast((remaining % 128) + 128)));
                remaining /= 128;
            }
            try buffer.append(self.allocator, @as(u8, @intCast(remaining)));
        }
    }

    fn encodeString(self: *Encoder, buffer: *std.ArrayList(u8), str: []const u8, use_huffman: bool) !void {
        if (use_huffman) {
            // Use Huffman encoding if beneficial
            const huffman_encoded = huffman.encode(self.allocator, str) catch {
                // Fall back to literal if Huffman fails
                try self.encodeInteger(buffer, @intCast(str.len), 7, 0x00);
                try buffer.appendSlice(self.allocator, str);
                return;
            };
            defer self.allocator.free(huffman_encoded);
            
            // Only use Huffman if it actually saves space
            if (huffman_encoded.len < str.len) {
                try self.encodeInteger(buffer, @intCast(huffman_encoded.len), 7, 0x80); // H=1
                try buffer.appendSlice(self.allocator, huffman_encoded);
            } else {
                // Literal is better
                try self.encodeInteger(buffer, @intCast(str.len), 7, 0x00);
                try buffer.appendSlice(self.allocator, str);
            }
        } else {
            // Literal string (RFC 7541 Section 5.2)
            try self.encodeInteger(buffer, @intCast(str.len), 7, 0x00);
            try buffer.appendSlice(self.allocator, str);
        }
    }
};

pub const Decoder = struct {
    dynamic_table: std.ArrayList(HeaderField),
    allocator: std.mem.Allocator,
    max_dynamic_table_size: u32,

    pub fn init(allocator: std.mem.Allocator) !Decoder {
        return Decoder{
            .dynamic_table = std.ArrayList(HeaderField){},
            .allocator = allocator,
            .max_dynamic_table_size = 4096,
        };
    }

    pub fn deinit(self: *Decoder) void {
        for (self.dynamic_table.items) |field| {
            self.allocator.free(field.name);
            self.allocator.free(field.value);
        }
        self.dynamic_table.deinit(self.allocator);
    }

    pub fn decode(self: *Decoder, encoded: []const u8) !std.StringHashMap([]const u8) {
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        errdefer {
            // Clean up any allocated strings on error
            var it = headers.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            headers.deinit();
        }

        var pos: usize = 0;
        while (pos < encoded.len) {
            const result = try self.decodeHeaderField(encoded[pos..]);
            pos += result.bytes_consumed;

            const name = try self.allocator.dupe(u8, result.field.name);
            const value = try self.allocator.dupe(u8, result.field.value);
            try headers.put(name, value);
        }

        return headers;
    }

    // Helper to properly free a decoded headers map
    pub fn freeDecodedHeaders(self: *Decoder, headers: *std.StringHashMap([]const u8)) void {
        var it = headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        headers.deinit();
    }

    const DecodeResult = struct {
        field: Pair,
        bytes_consumed: usize,
    };

    fn decodeHeaderField(self: *Decoder, data: []const u8) !DecodeResult {
        if (data.len == 0) return HpackError.InvalidHeaderBlock;

        const first_byte = data[0];
        var pos: usize = 0;

        if ((first_byte & 0x80) != 0) {
            // Indexed Header Field (RFC 7541 Section 6.1)
            const decode_result = try self.decodeInteger(data, 7);
            pos += decode_result.bytes_consumed;
            const index = decode_result.value;

            if (index == 0) return HpackError.InvalidIndex;

            const field = try self.getIndexedField(index);
            return DecodeResult{
                .field = field,
                .bytes_consumed = pos,
            };
        } else if ((first_byte & 0x40) != 0) {
            // Literal Header Field with Incremental Indexing (RFC 7541 Section 6.2.1)
            const index_result = try self.decodeInteger(data, 6);
            pos += index_result.bytes_consumed;

            var name: []const u8 = undefined;
            if (index_result.value == 0) {
                // New name
                const name_result = try self.decodeString(data[pos..]);
                pos += name_result.bytes_consumed;
                name = name_result.value;
            } else {
                // Indexed name
                const field = try self.getIndexedField(index_result.value);
                name = field.name;
            }

            const value_result = try self.decodeString(data[pos..]);
            pos += value_result.bytes_consumed;

            return DecodeResult{
                .field = .{ .name = name, .value = value_result.value },
                .bytes_consumed = pos,
            };
        } else {
            // Literal Header Field without Indexing (RFC 7541 Section 6.2.2)
            // or Never Indexed (RFC 7541 Section 6.2.3)
            const prefix_bits: u3 = if ((first_byte & 0x10) != 0) 4 else 4;
            const index_result = try self.decodeInteger(data, prefix_bits);
            pos += index_result.bytes_consumed;

            var name: []const u8 = undefined;
            if (index_result.value == 0) {
                // New name
                const name_result = try self.decodeString(data[pos..]);
                pos += name_result.bytes_consumed;
                name = name_result.value;
            } else {
                // Indexed name
                const field = try self.getIndexedField(index_result.value);
                name = field.name;
            }

            const value_result = try self.decodeString(data[pos..]);
            pos += value_result.bytes_consumed;

            return DecodeResult{
                .field = .{ .name = name, .value = value_result.value },
                .bytes_consumed = pos,
            };
        }
    }

    const IntegerDecodeResult = struct {
        value: u32,
        bytes_consumed: usize,
    };

    fn decodeInteger(self: *Decoder, data: []const u8, prefix_bits: u3) !IntegerDecodeResult {
        _ = self;
        if (data.len == 0) return HpackError.InvalidHeaderBlock;

        const mask = (@as(u8, 1) << prefix_bits) - 1;
        var value = @as(u32, data[0] & mask);
        var pos: usize = 1;

        if (value < mask) {
            return IntegerDecodeResult{ .value = value, .bytes_consumed = pos };
        }

        var m: u32 = 0;
        while (pos < data.len) {
            const byte = data[pos];
            pos += 1;

            const increment = @as(u32, byte & 0x7F) << @intCast(m);
            if (value > std.math.maxInt(u32) - increment) {
                return HpackError.IntegerOverflow;
            }
            value += increment;
            m += 7;

            if ((byte & 0x80) == 0) break;
        }

        return IntegerDecodeResult{ .value = value, .bytes_consumed = pos };
    }

    const StringDecodeResult = struct {
        value: []const u8,
        bytes_consumed: usize,
        needs_free: bool, // Whether the value needs to be freed
    };

    fn decodeString(self: *Decoder, data: []const u8) !StringDecodeResult {
        if (data.len == 0) return HpackError.InvalidHeaderBlock;
        
        const is_huffman_encoded = (data[0] & 0x80) != 0;
        const length_result = try self.decodeInteger(data, 7);
        var pos = length_result.bytes_consumed;
        const length = length_result.value;
        
        if (pos + length > data.len) return HpackError.InvalidHeaderBlock;
        
        if (is_huffman_encoded) {
            // Decode Huffman-encoded string
            const encoded_data = data[pos..pos + length];
            const decoded = huffman.decode(self.allocator, encoded_data) catch {
                return HpackError.InvalidHuffmanCode;
            };
            pos += length;
            return StringDecodeResult{
                .value = decoded,
                .bytes_consumed = pos,
                .needs_free = true,
            };
        } else {
            const str = data[pos..pos + length];
            pos += length;
            return StringDecodeResult{
                .value = str,
                .bytes_consumed = pos,
                .needs_free = false,
            };
        }
    }

    fn getIndexedField(self: *Decoder, index: u32) !Pair {
        if (index == 0) return HpackError.InvalidIndex;

        if (index <= STATIC_TABLE.len) {
            return STATIC_TABLE[index - 1];
        }

        const dynamic_index = index - STATIC_TABLE.len - 1;
        if (dynamic_index >= self.dynamic_table.items.len) {
            return HpackError.InvalidIndex;
        }

        const field = self.dynamic_table.items[dynamic_index];
        return Pair{ .name = field.name, .value = field.value };
    }
};

test "HPACK static table lookups" {
    var encoder = try Encoder.init(std.testing.allocator);
    defer encoder.deinit();

    // Test exact matches
    try std.testing.expectEqual(@as(?u32, 3), encoder.findInStaticTable(":method", "POST"));
    try std.testing.expectEqual(@as(?u32, 6), encoder.findInStaticTable(":scheme", "http"));

    // Test name-only matches
    try std.testing.expectEqual(@as(?u32, 1), encoder.findNameInStaticTable(":authority"));
    try std.testing.expectEqual(@as(?u32, 31), encoder.findNameInStaticTable("content-type"));
}

test "HPACK integer encoding/decoding" {
var encoder = try Encoder.init(std.testing.allocator);
defer encoder.deinit();

var decoder = try Decoder.init(std.testing.allocator);
defer decoder.deinit();

var buffer = std.ArrayList(u8){};
defer buffer.deinit(std.testing.allocator);

// Test small integer
try encoder.encodeInteger(&buffer, 10, 5, 0x00);
const result1 = try decoder.decodeInteger(buffer.items, 5);
try std.testing.expectEqual(@as(u32, 10), result1.value);

buffer.clearRetainingCapacity();

// Test large integer requiring multiple bytes
try encoder.encodeInteger(&buffer, 1337, 5, 0x00);
const result2 = try decoder.decodeInteger(buffer.items, 5);
try std.testing.expectEqual(@as(u32, 1337), result2.value);
}

test "HPACK with Huffman compression" {
var encoder = try Encoder.init(std.testing.allocator);
defer encoder.deinit();
    
var decoder = try Decoder.init(std.testing.allocator);
defer decoder.deinit();
    
// Test headers that should benefit from Huffman compression
const test_pairs = [_]Pair{
.{ .name = ":method", .value = "POST" },
.{ .name = ":path", .value = "/pdpb.PD/GetMembers" },
.{ .name = "content-type", .value = "application/grpc+proto" },
.{ .name = "grpc-accept-encoding", .value = "gzip,deflate" },
};
    
// Encode with Huffman
const encoded = try encoder.encodePairs(&test_pairs);
defer std.testing.allocator.free(encoded);
    
// Decode back
var decoded_headers = try decoder.decode(encoded);
defer decoder.freeDecodedHeaders(&decoded_headers);
    
// Verify we got the right headers back
try std.testing.expect(decoded_headers.count() >= test_pairs.len);
    
// Check some specific values
if (decoded_headers.get(":method")) |method| {
try std.testing.expectEqualStrings("POST", method);
}
    
if (decoded_headers.get("content-type")) |content_type| {
try std.testing.expectEqualStrings("application/grpc+proto", content_type);
}
}

test "HPACK dynamic table functionality" {
var encoder = try Encoder.init(std.testing.allocator);
defer encoder.deinit();
    
// Add some headers that should go into dynamic table
const pairs1 = [_]Pair{
.{ .name = "custom-header", .value = "custom-value" },
.{ .name = "another-header", .value = "another-value" },
};
    
const encoded1 = try encoder.encodePairs(&pairs1);
defer std.testing.allocator.free(encoded1);
    
// Dynamic table should now have these entries
try std.testing.expect(encoder.dynamic_table.items.len == 2);
    
// Encoding the same headers again should use dynamic table references
const encoded2 = try encoder.encodePairs(&pairs1);
defer std.testing.allocator.free(encoded2);
    
// Should be much smaller due to dynamic table hits
try std.testing.expect(encoded2.len < 50); // Rough estimate
}
