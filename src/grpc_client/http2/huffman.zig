const std = @import("std");

pub const HuffmanError = error{
    InvalidSymbol,
    InvalidPadding,
    BufferTooSmall,
};

// RFC 7541 Appendix B - Huffman Code Table
const HuffmanCode = struct {
    code: u32,
    bits: u8,
};

// Huffman codes for symbols 0-255 (RFC 7541 Appendix B)
const HUFFMAN_CODES = [256]HuffmanCode{
    .{ .code = 0x1ff8, .bits = 13 }, // 0
    .{ .code = 0x7fffd8, .bits = 23 }, // 1
    .{ .code = 0xfffffe2, .bits = 28 }, // 2
    .{ .code = 0xfffffe3, .bits = 28 }, // 3
    .{ .code = 0xfffffe4, .bits = 28 }, // 4
    .{ .code = 0xfffffe5, .bits = 28 }, // 5
    .{ .code = 0xfffffe6, .bits = 28 }, // 6
    .{ .code = 0xfffffe7, .bits = 28 }, // 7
    .{ .code = 0xfffffe8, .bits = 28 }, // 8
    .{ .code = 0xffffea, .bits = 24 }, // 9
    .{ .code = 0x3ffffffc, .bits = 30 }, // 10
    .{ .code = 0xfffffe9, .bits = 28 }, // 11
    .{ .code = 0xfffffea, .bits = 28 }, // 12
    .{ .code = 0x3ffffffd, .bits = 30 }, // 13
    .{ .code = 0xfffffeb, .bits = 28 }, // 14
    .{ .code = 0xfffffec, .bits = 28 }, // 15
    .{ .code = 0xfffffed, .bits = 28 }, // 16
    .{ .code = 0xfffffee, .bits = 28 }, // 17
    .{ .code = 0xfffffef, .bits = 28 }, // 18
    .{ .code = 0xffffff0, .bits = 28 }, // 19
    .{ .code = 0xffffff1, .bits = 28 }, // 20
    .{ .code = 0xffffff2, .bits = 28 }, // 21
    .{ .code = 0x3ffffffe, .bits = 30 }, // 22
    .{ .code = 0xffffff3, .bits = 28 }, // 23
    .{ .code = 0xffffff4, .bits = 28 }, // 24
    .{ .code = 0xffffff5, .bits = 28 }, // 25
    .{ .code = 0xffffff6, .bits = 28 }, // 26
    .{ .code = 0xffffff7, .bits = 28 }, // 27
    .{ .code = 0xffffff8, .bits = 28 }, // 28
    .{ .code = 0xffffff9, .bits = 28 }, // 29
    .{ .code = 0xffffffa, .bits = 28 }, // 30
    .{ .code = 0xffffffb, .bits = 28 }, // 31
    .{ .code = 0x14, .bits = 6 }, // 32 ' '
    .{ .code = 0x3f8, .bits = 10 }, // 33 '!'
    .{ .code = 0x3f9, .bits = 10 }, // 34 '"'
    .{ .code = 0xffa, .bits = 12 }, // 35 '#'
    .{ .code = 0x1ff9, .bits = 13 }, // 36 '$'
    .{ .code = 0x15, .bits = 6 }, // 37 '%'
    .{ .code = 0xf8, .bits = 8 }, // 38 '&'
    .{ .code = 0x7fa, .bits = 11 }, // 39 '\''
    .{ .code = 0x3fa, .bits = 10 }, // 40 '('
    .{ .code = 0x3fb, .bits = 10 }, // 41 ')'
    .{ .code = 0xf9, .bits = 8 }, // 42 '*'
    .{ .code = 0x7fb, .bits = 11 }, // 43 '+'
    .{ .code = 0xfa, .bits = 8 }, // 44 ','
    .{ .code = 0x16, .bits = 6 }, // 45 '-'
    .{ .code = 0x17, .bits = 6 }, // 46 '.'
    .{ .code = 0x18, .bits = 6 }, // 47 '/'
    .{ .code = 0x0, .bits = 5 }, // 48 '0'
    .{ .code = 0x1, .bits = 5 }, // 49 '1'
    .{ .code = 0x2, .bits = 5 }, // 50 '2'
    .{ .code = 0x19, .bits = 6 }, // 51 '3'
    .{ .code = 0x1a, .bits = 6 }, // 52 '4'
    .{ .code = 0x1b, .bits = 6 }, // 53 '5'
    .{ .code = 0x1c, .bits = 6 }, // 54 '6'
    .{ .code = 0x1d, .bits = 6 }, // 55 '7'
    .{ .code = 0x1e, .bits = 6 }, // 56 '8'
    .{ .code = 0x1f, .bits = 6 }, // 57 '9'
    .{ .code = 0x5c, .bits = 7 }, // 58 ':'
    .{ .code = 0xfb, .bits = 8 }, // 59 ';'
    .{ .code = 0x7ffc, .bits = 15 }, // 60 '<'
    .{ .code = 0x20, .bits = 6 }, // 61 '='
    .{ .code = 0xffb, .bits = 12 }, // 62 '>'
    .{ .code = 0x3fc, .bits = 10 }, // 63 '?'
    .{ .code = 0x1ffa, .bits = 13 }, // 64 '@'
    .{ .code = 0x21, .bits = 6 }, // 65 'A'
    .{ .code = 0x5d, .bits = 7 }, // 66 'B'
    .{ .code = 0x5e, .bits = 7 }, // 67 'C'
    .{ .code = 0x5f, .bits = 7 }, // 68 'D'
    .{ .code = 0x60, .bits = 7 }, // 69 'E'
    .{ .code = 0x61, .bits = 7 }, // 70 'F'
    .{ .code = 0x62, .bits = 7 }, // 71 'G'
    .{ .code = 0x63, .bits = 7 }, // 72 'H'
    .{ .code = 0x64, .bits = 7 }, // 73 'I'
    .{ .code = 0x65, .bits = 7 }, // 74 'J'
    .{ .code = 0x66, .bits = 7 }, // 75 'K'
    .{ .code = 0x67, .bits = 7 }, // 76 'L'
    .{ .code = 0x68, .bits = 7 }, // 77 'M'
    .{ .code = 0x69, .bits = 7 }, // 78 'N'
    .{ .code = 0x6a, .bits = 7 }, // 79 'O'
    .{ .code = 0x6b, .bits = 7 }, // 80 'P'
    .{ .code = 0x6c, .bits = 7 }, // 81 'Q'
    .{ .code = 0x6d, .bits = 7 }, // 82 'R'
    .{ .code = 0x6e, .bits = 7 }, // 83 'S'
    .{ .code = 0x6f, .bits = 7 }, // 84 'T'
    .{ .code = 0x70, .bits = 7 }, // 85 'U'
    .{ .code = 0x71, .bits = 7 }, // 86 'V'
    .{ .code = 0x72, .bits = 7 }, // 87 'W'
    .{ .code = 0xfc, .bits = 8 }, // 88 'X'
    .{ .code = 0x73, .bits = 7 }, // 89 'Y'
    .{ .code = 0xfd, .bits = 8 }, // 90 'Z'
    .{ .code = 0x1ffb, .bits = 13 }, // 91 '['
    .{ .code = 0x7fff0, .bits = 19 }, // 92 '\'
    .{ .code = 0x1ffc, .bits = 13 }, // 93 ']'
    .{ .code = 0x3ffc, .bits = 14 }, // 94 '^'
    .{ .code = 0x22, .bits = 6 }, // 95 '_'
    .{ .code = 0x7ffd, .bits = 15 }, // 96 '`'
    .{ .code = 0x3, .bits = 5 }, // 97 'a'
    .{ .code = 0x23, .bits = 6 }, // 98 'b'
    .{ .code = 0x4, .bits = 5 }, // 99 'c'
    .{ .code = 0x24, .bits = 6 }, // 100 'd'
    .{ .code = 0x5, .bits = 5 }, // 101 'e'
    .{ .code = 0x25, .bits = 6 }, // 102 'f'
    .{ .code = 0x26, .bits = 6 }, // 103 'g'
    .{ .code = 0x27, .bits = 6 }, // 104 'h'
    .{ .code = 0x6, .bits = 5 }, // 105 'i'
    .{ .code = 0x74, .bits = 7 }, // 106 'j'
    .{ .code = 0x75, .bits = 7 }, // 107 'k'
    .{ .code = 0x28, .bits = 6 }, // 108 'l'
    .{ .code = 0x29, .bits = 6 }, // 109 'm'
    .{ .code = 0x2a, .bits = 6 }, // 110 'n'
    .{ .code = 0x7, .bits = 5 }, // 111 'o'
    .{ .code = 0x2b, .bits = 6 }, // 112 'p'
    .{ .code = 0x76, .bits = 7 }, // 113 'q'
    .{ .code = 0x2c, .bits = 6 }, // 114 'r'
    .{ .code = 0x8, .bits = 5 }, // 115 's'
    .{ .code = 0x9, .bits = 5 }, // 116 't'
    .{ .code = 0x2d, .bits = 6 }, // 117 'u'
    .{ .code = 0x77, .bits = 7 }, // 118 'v'
    .{ .code = 0x78, .bits = 7 }, // 119 'w'
    .{ .code = 0x79, .bits = 7 }, // 120 'x'
    .{ .code = 0x7a, .bits = 7 }, // 121 'y'
    .{ .code = 0x7b, .bits = 7 }, // 122 'z'
    // Continue with remaining symbols...
    .{ .code = 0x7ffe, .bits = 15 }, // 123 '{'
    .{ .code = 0x7fc, .bits = 11 }, // 124 '|'
    .{ .code = 0x3ffd, .bits = 14 }, // 125 '}'
    .{ .code = 0x1ffd, .bits = 13 }, // 126 '~'
    .{ .code = 0xffffffc, .bits = 28 }, // 127
    // Symbols 128-255 (mostly 28-30 bit codes)
    .{ .code = 0xfffe6, .bits = 20 }, // 128
    .{ .code = 0x3fffd2, .bits = 22 }, // 129
    .{ .code = 0xfffe7, .bits = 20 }, // 130
    .{ .code = 0xfffe8, .bits = 20 }, // 131
    .{ .code = 0x3fffd3, .bits = 22 }, // 132
    .{ .code = 0x3fffd4, .bits = 22 }, // 133
    .{ .code = 0x3fffd5, .bits = 22 }, // 134
    .{ .code = 0x7fffd9, .bits = 23 }, // 135
    .{ .code = 0x3fffd6, .bits = 22 }, // 136
    .{ .code = 0x7fffda, .bits = 23 }, // 137
    .{ .code = 0x7fffdb, .bits = 23 }, // 138
    .{ .code = 0x7fffdc, .bits = 23 }, // 139
    .{ .code = 0x7fffdd, .bits = 23 }, // 140
    .{ .code = 0x7fffde, .bits = 23 }, // 141
    .{ .code = 0xffffeb, .bits = 24 }, // 142
    .{ .code = 0x7fffdf, .bits = 23 }, // 143
    .{ .code = 0xffffec, .bits = 24 }, // 144
    .{ .code = 0xffffed, .bits = 24 }, // 145
    .{ .code = 0x3fffd7, .bits = 22 }, // 146
    .{ .code = 0x7fffe0, .bits = 23 }, // 147
    .{ .code = 0xffffee, .bits = 24 }, // 148
    .{ .code = 0x7fffe1, .bits = 23 }, // 149
    .{ .code = 0x7fffe2, .bits = 23 }, // 150
    .{ .code = 0x7fffe3, .bits = 23 }, // 151
    .{ .code = 0x7fffe4, .bits = 23 }, // 152
    .{ .code = 0x1fffdc, .bits = 21 }, // 153
    .{ .code = 0x3fffd8, .bits = 22 }, // 154
    .{ .code = 0x7fffe5, .bits = 23 }, // 155
    .{ .code = 0x3fffd9, .bits = 22 }, // 156
    .{ .code = 0x7fffe6, .bits = 23 }, // 157
    .{ .code = 0x7fffe7, .bits = 23 }, // 158
    .{ .code = 0xffffef, .bits = 24 }, // 159
    .{ .code = 0x3fffda, .bits = 22 }, // 160
    .{ .code = 0x1fffdd, .bits = 21 }, // 161
    .{ .code = 0xfffe9, .bits = 20 }, // 162
    .{ .code = 0x3fffdb, .bits = 22 }, // 163
    .{ .code = 0x3fffdc, .bits = 22 }, // 164
    .{ .code = 0x7fffe8, .bits = 23 }, // 165
    .{ .code = 0x7fffe9, .bits = 23 }, // 166
    .{ .code = 0x1fffde, .bits = 21 }, // 167
    .{ .code = 0x7fffea, .bits = 23 }, // 168
    .{ .code = 0x3fffdd, .bits = 22 }, // 169
    .{ .code = 0x3fffde, .bits = 22 }, // 170
    .{ .code = 0xfffff0, .bits = 24 }, // 171
    .{ .code = 0x1fffdf, .bits = 21 }, // 172
    .{ .code = 0x3fffdf, .bits = 22 }, // 173
    .{ .code = 0x7fffeb, .bits = 23 }, // 174
    .{ .code = 0x7fffec, .bits = 23 }, // 175
    .{ .code = 0x1fffe0, .bits = 21 }, // 176
    .{ .code = 0x1fffe1, .bits = 21 }, // 177
    .{ .code = 0x3fffe0, .bits = 22 }, // 178
    .{ .code = 0x1fffe2, .bits = 21 }, // 179
    .{ .code = 0x7fffed, .bits = 23 }, // 180
    .{ .code = 0x3fffe1, .bits = 22 }, // 181
    .{ .code = 0x7fffee, .bits = 23 }, // 182
    .{ .code = 0x7fffef, .bits = 23 }, // 183
    .{ .code = 0xfffea, .bits = 20 }, // 184
    .{ .code = 0x3fffe2, .bits = 22 }, // 185
    .{ .code = 0x3fffe3, .bits = 22 }, // 186
    .{ .code = 0x3fffe4, .bits = 22 }, // 187
    .{ .code = 0x7ffff0, .bits = 23 }, // 188
    .{ .code = 0x3fffe5, .bits = 22 }, // 189
    .{ .code = 0x3fffe6, .bits = 22 }, // 190
    .{ .code = 0x7ffff1, .bits = 23 }, // 191
    .{ .code = 0x3ffffe0, .bits = 26 }, // 192
    .{ .code = 0x3ffffe1, .bits = 26 }, // 193
    .{ .code = 0xfffeb, .bits = 20 }, // 194
    .{ .code = 0x7fff1, .bits = 19 }, // 195
    .{ .code = 0x3fffe7, .bits = 22 }, // 196
    .{ .code = 0x7ffff2, .bits = 23 }, // 197
    .{ .code = 0x3fffe8, .bits = 22 }, // 198
    .{ .code = 0x1ffffec, .bits = 25 }, // 199
    .{ .code = 0x3ffffe2, .bits = 26 }, // 200
    .{ .code = 0x3ffffe3, .bits = 26 }, // 201
    .{ .code = 0x3ffffe4, .bits = 26 }, // 202
    .{ .code = 0x7ffffde, .bits = 27 }, // 203
    .{ .code = 0x7ffffdf, .bits = 27 }, // 204
    .{ .code = 0x3ffffe5, .bits = 26 }, // 205
    .{ .code = 0xfffff1, .bits = 24 }, // 206
    .{ .code = 0x1ffffed, .bits = 25 }, // 207
    .{ .code = 0x7fff2, .bits = 19 }, // 208
    .{ .code = 0x1fffe3, .bits = 21 }, // 209
    .{ .code = 0x3ffffe6, .bits = 26 }, // 210
    .{ .code = 0x7ffffe0, .bits = 27 }, // 211
    .{ .code = 0x7ffffe1, .bits = 27 }, // 212
    .{ .code = 0x3ffffe7, .bits = 26 }, // 213
    .{ .code = 0x7ffffe2, .bits = 27 }, // 214
    .{ .code = 0xfffff2, .bits = 24 }, // 215
    .{ .code = 0x1fffe4, .bits = 21 }, // 216
    .{ .code = 0x1fffe5, .bits = 21 }, // 217
    .{ .code = 0x3ffffe8, .bits = 26 }, // 218
    .{ .code = 0x3ffffe9, .bits = 26 }, // 219
    .{ .code = 0xffffffd, .bits = 28 }, // 220
    .{ .code = 0x7ffffe3, .bits = 27 }, // 221
    .{ .code = 0x7ffffe4, .bits = 27 }, // 222
    .{ .code = 0x7ffffe5, .bits = 27 }, // 223
    .{ .code = 0xfffec, .bits = 20 }, // 224
    .{ .code = 0xfffff3, .bits = 24 }, // 225
    .{ .code = 0xfffed, .bits = 20 }, // 226
    .{ .code = 0x1fffe6, .bits = 21 }, // 227
    .{ .code = 0x3fffe9, .bits = 22 }, // 228
    .{ .code = 0x1fffe7, .bits = 21 }, // 229
    .{ .code = 0x1fffe8, .bits = 21 }, // 230
    .{ .code = 0x7ffff3, .bits = 23 }, // 231
    .{ .code = 0x3fffea, .bits = 22 }, // 232
    .{ .code = 0x3fffeb, .bits = 22 }, // 233
    .{ .code = 0x1ffffee, .bits = 25 }, // 234
    .{ .code = 0x1ffffef, .bits = 25 }, // 235
    .{ .code = 0xfffff4, .bits = 24 }, // 236
    .{ .code = 0xfffff5, .bits = 24 }, // 237
    .{ .code = 0x3ffffea, .bits = 26 }, // 238
    .{ .code = 0x7ffff4, .bits = 23 }, // 239
    .{ .code = 0x3ffffeb, .bits = 26 }, // 240
    .{ .code = 0x7ffffe6, .bits = 27 }, // 241
    .{ .code = 0x3ffffec, .bits = 26 }, // 242
    .{ .code = 0x3ffffed, .bits = 26 }, // 243
    .{ .code = 0x7ffffe7, .bits = 27 }, // 244
    .{ .code = 0x7ffffe8, .bits = 27 }, // 245
    .{ .code = 0x7ffffe9, .bits = 27 }, // 246
    .{ .code = 0x7ffffea, .bits = 27 }, // 247
    .{ .code = 0x7ffffeb, .bits = 27 }, // 248
    .{ .code = 0xffffffe, .bits = 28 }, // 249
    .{ .code = 0x7ffffec, .bits = 27 }, // 250
    .{ .code = 0x7ffffed, .bits = 27 }, // 251
    .{ .code = 0x7ffffee, .bits = 27 }, // 252
    .{ .code = 0x7ffffef, .bits = 27 }, // 253
    .{ .code = 0x7fffff0, .bits = 27 }, // 254
    .{ .code = 0x3ffffee, .bits = 26 }, // 255
};

const EOS_CODE = HuffmanCode{ .code = 0x3fffffff, .bits = 30 }; // End of string

pub fn encode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var bit_buffer: u64 = 0;
    var bit_count: u8 = 0;
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    for (input) |byte| {
        const huff_code = HUFFMAN_CODES[byte];

        // Add bits to buffer - cast bits to u6 for shift operation
        const shift_amount = @as(u6, @intCast(huff_code.bits));
        bit_buffer = (bit_buffer << shift_amount) | huff_code.code;
        bit_count += huff_code.bits;

        // Output complete bytes
        while (bit_count >= 8) {
            const output_shift = @as(u6, @intCast(bit_count - 8));
            const output_byte = @as(u8, @intCast((bit_buffer >> output_shift) & 0xFF));
            try output.append(allocator, output_byte);
            bit_count -= 8;
        }
    }

    // Handle remaining bits with padding
    if (bit_count > 0) {
        const padding_bits = 8 - bit_count;
        const padding = (@as(u64, 1) << @as(u6, @intCast(padding_bits))) - 1; // All 1s for padding
        bit_buffer = (bit_buffer << @as(u6, @intCast(padding_bits))) | padding;
        const output_byte = @as(u8, @intCast(bit_buffer & 0xFF));
        try output.append(allocator, output_byte);
    }

    return output.toOwnedSlice(allocator);
}

// Decode tree node for Huffman decoding
const DecodeNode = struct {
    symbol: ?u8 = null, // null for internal nodes
    left: ?*DecodeNode = null,
    right: ?*DecodeNode = null,
};

// Huffman decoder with its own decode tree
pub const HuffmanDecoder = struct {
    decode_tree: *DecodeNode,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !HuffmanDecoder {
        const tree = try buildDecodeTree(allocator);
        return HuffmanDecoder{
            .decode_tree = tree,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HuffmanDecoder) void {
        freeDecodeTree(self.allocator, self.decode_tree);
        self.allocator.destroy(self.decode_tree);
    }

    pub fn decode(self: *HuffmanDecoder, input: []const u8) ![]u8 {
        var output = std.ArrayList(u8){};
        defer output.deinit(self.allocator);

        var current = self.decode_tree;
        var bit_buffer: u32 = 0;
        var bit_count: u8 = 0;

        for (input) |byte| {
            bit_buffer = (bit_buffer << 8) | byte;
            bit_count += 8;

            // Process bits
            while (bit_count > 0) {
                bit_count -= 1;
                const bit = (bit_buffer >> @as(u5, @intCast(bit_count))) & 1;

                // Traverse tree
                if (bit == 0) {
                    current = current.left orelse return HuffmanError.InvalidSymbol;
                } else {
                    current = current.right orelse return HuffmanError.InvalidSymbol;
                }

                // Check if we reached a symbol
                if (current.symbol) |symbol| {
                    try output.append(self.allocator, symbol);
                    current = self.decode_tree; // Reset to root
                }
            }
        }

        // Check for valid padding (should be at root or valid padding bits)
        if (current != self.decode_tree) {
            // We're in the middle of decoding - check if remaining path is valid padding
            // Valid padding is all 1s that lead to EOS or are shorter than EOS
            return HuffmanError.InvalidPadding;
        }

        return output.toOwnedSlice(self.allocator);
    }
};

fn buildDecodeTree(allocator: std.mem.Allocator) !*DecodeNode {
    const root = try allocator.create(DecodeNode);
    root.* = DecodeNode{};

    // Build tree from all codes
    for (HUFFMAN_CODES, 0..) |huff_code, symbol| {
        var current = root;
        const code_value = huff_code.code;
        var bits_left = huff_code.bits;

        // Traverse from MSB to LSB
        while (bits_left > 0) {
            bits_left -= 1;
            const bit = (code_value >> @as(u5, @intCast(bits_left))) & 1;

            if (bits_left == 0) {
                // Leaf node - store symbol
                if (bit == 0) {
                    if (current.left == null) {
                        current.left = try allocator.create(DecodeNode);
                        current.left.?.* = DecodeNode{};
                    }
                    current.left.?.symbol = @intCast(symbol);
                } else {
                    if (current.right == null) {
                        current.right = try allocator.create(DecodeNode);
                        current.right.?.* = DecodeNode{};
                    }
                    current.right.?.symbol = @intCast(symbol);
                }
            } else {
                // Internal node - continue traversal
                if (bit == 0) {
                    if (current.left == null) {
                        current.left = try allocator.create(DecodeNode);
                        current.left.?.* = DecodeNode{};
                    }
                    current = current.left.?;
                } else {
                    if (current.right == null) {
                        current.right = try allocator.create(DecodeNode);
                        current.right.?.* = DecodeNode{};
                    }
                    current = current.right.?;
                }
            }
        }
    }

    return root;
}

// Simple wrapper function for backward compatibility
pub fn decode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var decoder = try HuffmanDecoder.init(allocator);
    defer decoder.deinit();
    return try decoder.decode(input);
}

fn freeDecodeTree(allocator: std.mem.Allocator, node: *DecodeNode) void {
    if (node.left) |left| {
        freeDecodeTree(allocator, left);
        allocator.destroy(left);
    }
    if (node.right) |right| {
        freeDecodeTree(allocator, right);
        allocator.destroy(right);
    }
}

// Estimate encoded size (useful for deciding whether to use Huffman)
pub fn estimateEncodedSize(input: []const u8) usize {
    var total_bits: usize = 0;
    for (input) |byte| {
        total_bits += HUFFMAN_CODES[byte].bits;
    }
    return (total_bits + 7) / 8; // Round up to bytes
}

test "Huffman encode common strings" {
    const allocator = std.testing.allocator;

    // Test encoding "www.example.com"
    const input = "www.example.com";
    const encoded = try encode(allocator, input);
    defer allocator.free(encoded);

    // Should be significantly smaller than input
    try std.testing.expect(encoded.len < input.len);

    // Test estimate
    const estimated = estimateEncodedSize(input);
    try std.testing.expect(estimated <= encoded.len);
}

test "Huffman encode HTTP headers" {
    const allocator = std.testing.allocator;

    // Common header values
    const values = [_][]const u8{
        "application/grpc+proto",
        "gzip,deflate",
        "127.0.0.1:2379",
        "/pdpb.PD/GetMembers",
    };

    for (values) |value| {
        const encoded = try encode(allocator, value);
        defer allocator.free(encoded);

        // Huffman should compress these common patterns
        const compression_ratio = @as(f32, @floatFromInt(encoded.len)) / @as(f32, @floatFromInt(value.len));
        std.debug.print("'{s}': {d} -> {d} bytes (ratio: {d:.2})\n", .{ value, value.len, encoded.len, compression_ratio });
    }
}
