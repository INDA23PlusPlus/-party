// Copied from an older project.
// Kindly, inquire before making any changes.

const std = @import("std");

const Error = error{ UnknownCode, IncorrectType, MissingBytes, NoMoreData, UnreadItemsInSequence, AlreadyOpen, OutdatedContext, InvalidString, TooLongSequence };

pub const Scanner = struct {
    /// CBOR.
    data: []const u8 = "",

    /// What byte is being parsed.
    pos: usize = 0,

    /// The current structural depth of the scan.
    depth: u32 = 0,

    /// Protects against accidentally reusing a scanner improperly.
    /// 333 is used to increase detection chances if the stack is corrupted.
    reuse: u16 = 333,

    pub fn begin(scanner: *Scanner, data: []const u8) Context {
        // We add some pseudo-randomness to increase detection chances.
        const reuse = scanner.reuse +% 1 +% (@as(u16, @truncate(@intFromPtr(data.ptr))) >> 2);
        scanner.reuse = reuse;
        scanner.data = data;
        scanner.depth = 0;
        scanner.pos = 0;
        return .{
            .scanner = scanner,
            .depth = 0,
            .reuse = reuse,
            .items = std.math.maxInt(usize),
        };
    }
};

const AnyValue = union(enum) {
    array: u64,
    number: u64,
    negative_number: u64,
    string: []const u8,
    bin: []const u8,
    unchecked_str: []const u8,
};

const small_usize = @typeInfo(usize).Int.bits < 64;

pub const Context = struct {
    scanner: *Scanner,
    items: u64,
    depth: u32,
    reuse: u16,

    fn getNBytes(ctx: *Context, starting: usize, length: u64) ![]const u8 {
        // TODO: See if small_usize is even required.
        if (small_usize and length > std.math.maxInt(usize)) {
            return Error.TooLongSequence;
        }
        const end: usize = @truncate(starting + length);
        ctx.scanner.pos = end;
        if (starting + length > ctx.scanner.data.len) {
            return Error.MissingBytes;
        }
        return ctx.scanner.data[starting..end];
    }

    inline fn getU(ctx: *Context, starting: usize, comptime T: type) !T {
        const len = @typeInfo(T).Int.bits / 8;
        const end = starting + len;
        ctx.scanner.pos = end;
        if (end > ctx.scanner.data.len) {
            return Error.MissingBytes;
        }
        return std.mem.readInt(T, ctx.scanner.data[starting..].ptr[0..len], std.builtin.Endian.big);
    }
    fn readAny(ctx: *Context) !AnyValue {
        if (ctx.reuse != ctx.scanner.reuse) {
            return Error.OutdatedContext;
        }
        if (ctx.items == 0) {
            return Error.NoMoreData;
        }
        const pos = ctx.scanner.pos;
        if (pos >= ctx.scanner.data.len) {
            return Error.MissingBytes;
        }
        if (ctx.depth != ctx.scanner.depth) {
            return Error.UnreadItemsInSequence;
        }
        ctx.items -= 1;
        if (ctx.items == 0) {
            ctx.scanner.depth -= 1;
        }
        switch (ctx.scanner.data[pos]) {
            inline 0x00...0x17 => |s| {
                ctx.scanner.pos = pos + 1;
                return AnyValue{ .number = s };
            },
            0x18 => {
                return AnyValue{ .number = try ctx.getU(pos + 1, u8) };
            },
            0x19 => {
                return AnyValue{ .number = try ctx.getU(pos + 1, u16) };
            },
            0x1a => {
                return AnyValue{ .number = try ctx.getU(pos + 1, u32) };
            },
            0x1b => {
                return AnyValue{ .number = try ctx.getU(pos + 1, u64) };
            },
            inline 0x20...0x37 => |n| {
                ctx.scanner.pos = pos + 1;
                return AnyValue{ .negative_number = n - 0x20 };
            },
            0x38 => {
                return AnyValue{ .negative_number = try ctx.getU(pos + 1, u8) };
            },
            0x39 => {
                return AnyValue{ .negative_number = try ctx.getU(pos + 1, u16) };
            },
            0x3a => {
                return AnyValue{ .negative_number = try ctx.getU(pos + 1, u32) };
            },
            0x3b => {
                return AnyValue{ .negative_number = try ctx.getU(pos + 1, u64) };
            },
            0x40...0x57 => |l| {
                const len = l - 0x40;
                return AnyValue{ .bin = try ctx.getNBytes(pos + 1, len) };
            },
            0x58 => {
                const len = try ctx.getU(pos + 1, u8);
                return AnyValue{ .bin = try ctx.getNBytes(pos + 2, len) };
            },
            0x59 => {
                const len = try ctx.getU(pos + 1, u16);
                return AnyValue{ .bin = try ctx.getNBytes(pos + 3, len) };
            },
            0x5a => {
                const len = try ctx.getU(pos + 1, u32);
                return AnyValue{ .bin = try ctx.getNBytes(pos + 5, len) };
            },
            0x5b => {
                const len = try ctx.getU(pos + 1, u64);
                return AnyValue{ .bin = try ctx.getNBytes(pos + 9, len) };
            },
            0x60...0x77 => |l| {
                const len = l - 0x60;
                const str = try ctx.getNBytes(pos + 1, len);
                return AnyValue{ .unchecked_str = str };
            },
            0x78 => {
                const len = try ctx.getU(pos + 1, u8);
                const str = try ctx.getNBytes(pos + 2, len);
                return AnyValue{ .unchecked_str = str };
            },
            0x79 => {
                const len = try ctx.getU(pos + 1, u16);
                const str = try ctx.getNBytes(pos + 3, len);
                return AnyValue{ .unchecked_str = str };
            },
            0x7a => {
                const len = try ctx.getU(pos + 1, u32);
                const str = try ctx.getNBytes(pos + 5, len);
                return AnyValue{ .unchecked_str = str };
            },
            0x7b => {
                const len = try ctx.getU(pos + 1, u64);
                const str = try ctx.getNBytes(pos + 9, len);
                return AnyValue{ .unchecked_str = str };
            },
            inline 0x80...0x97 => |code| {
                const count = code - 0x80;
                ctx.scanner.pos = pos + 1;
                ctx.scanner.depth += 1;
                return AnyValue{ .array = count };
            },
            0x98 => {
                const count = try ctx.getU(pos + 1, u8);
                ctx.scanner.depth += 1;
                return AnyValue{ .array = count };
            },
            0x99 => {
                const count = try ctx.getU(pos + 1, u16);
                ctx.scanner.depth += 1;
                return AnyValue{ .array = count };
            },
            0x9a => {
                const count = try ctx.getU(pos + 1, u32);
                ctx.scanner.depth += 1;
                return AnyValue{ .array = count };
            },
            0x9b => {
                const count = try ctx.getU(pos + 1, u64);
                ctx.scanner.depth += 1;
                return AnyValue{ .array = count };
            },
            else => return Error.UnknownCode,
        }
    }

    pub fn readU64(ctx: *Context) !u64 {
        switch (try ctx.readAny()) {
            .number, .negative_number => |n| return n,
            else => return Error.IncorrectType,
        }
    }

    fn readI64(ctx: *Context) !i64 {
        switch (try ctx.readAny()) {
            .number => |n| return @intCast(n),
            .negative_number => |n| return -1 - @as(i64, @intCast(n)),
            else => return Error.IncorrectType,
        }
    }

    pub fn readBin(ctx: *Context) ![]const u8 {
        switch (try ctx.readAny()) {
            .bin => |s| return s,
            else => return Error.IncorrectType,
        }
    }

    pub fn readStr(ctx: *Context) ![]const u8 {
        switch (try ctx.readAny()) {
            .unchecked_str => |s| {
                if (std.unicode.utf8ValidateSlice(s)) {
                    return s;
                }
                return Error.InvalidString;
            },
            else => return Error.IncorrectType,
        }
    }

    pub fn readArray(ctx: *Context) !Context {
        switch (try ctx.readAny()) {
            .array => |n| return Context {
                .scanner = ctx.scanner,
                .depth = ctx.depth + 1,
                .items = n,
                .reuse = ctx.reuse,
            },
            else => return Error.IncorrectType,
        }
    }
};

pub fn writeBin(writer: anytype, str: []const u8) !void {
    if (str.len <= 23) {
        try writer.writeByte(0x40 + @as(u8, @truncate(str.len)));
        try writer.writeAll(str);
    } else if (str.len <= 255) {
        var a = [2]u8{0x58, @truncate(str.len)};
        try writer.writeAll(&a);
        try writer.writeAll(str);
    } else if (str.len <= 65535) {
        var a = [3]u8{0x59, 0, 0};
        std.mem.writeInt(std.math.ByteAlignedInt(u16), a[1..], @truncate(str.len), std.builtin.Endian.big);
        try writer.writeAll(&a);
        try writer.writeAll(str);
    } else if (str.len <= 0xFFFFFFFF) {
        var a = [5]u8{0x5a, 0, 0, 0, 0};
        std.mem.writeInt(std.math.ByteAlignedInt(u32), a[1..], @truncate(str.len), std.builtin.Endian.big);
        try writer.writeAll(&a);
        try writer.writeAll(str);
    } else {
        var a = [9]u8{0x5b, 0, 0, 0, 0, 0, 0, 0, 0};
        std.mem.writeInt(std.math.ByteAlignedInt(u64), a[1..], @truncate(str.len), std.builtin.Endian.big);
        try writer.writeAll(&a);
        try writer.writeAll(str);
    }
}

pub fn writeArrayHeader(writer: anytype, item_count: usize) !void {
    if (item_count <= 23) {
        try writer.writeByte(0x80 + @as(u8, @truncate(item_count)));
    } else if (item_count <= 255) {
        var a = [2]u8{0x98, @truncate(item_count)};
        try writer.writeAll(&a);
    } else if (item_count <= 65535) {
        var a = [3]u8{0x99, 0, 0};
        std.mem.writeInt(std.math.ByteAlignedInt(u16), a[1..], @truncate(item_count), std.builtin.Endian.big);
        try writer.writeAll(&a);
    } else if (item_count <= 0xFFFFFFFF) {
        var a = [5]u8{0x9a, 0, 0, 0, 0};
        std.mem.writeInt(std.math.ByteAlignedInt(u32), a[1..], @truncate(item_count), std.builtin.Endian.big);
        try writer.writeAll(&a);
    } else {
        var a = [9]u8{0x9b, 0, 0, 0, 0, 0, 0, 0, 0};
        std.mem.writeInt(std.math.ByteAlignedInt(u64), a[1..], @truncate(item_count), std.builtin.Endian.big);
        try writer.writeAll(&a);
    }
}


test "write CBOR fixbin" {
    var output = [_]u8{0} ** 256;
    var fb = std.io.fixedBufferStream(&output);
    const writer = fb.writer();
    try writeBin(writer, "xaxaxaxaxa");
    try std.testing.expectEqualStrings("\x4axaxaxaxaxa\x00", output[0..12]);
}

test "write CBOR bin 8" {
    var output = [_]u8{0} ** 256;
    var fb = std.io.fixedBufferStream(&output);
    const writer = fb.writer();
    try writeBin(writer, "a" ** 100);
    try std.testing.expectEqualStrings("\x58\x64" ++ ("a" ** 100) ++ "\x00", output[0..103]);
}

test "write CBOR bin 16" {
    var output = [_]u8{0} ** 2048;
    var fb = std.io.fixedBufferStream(&output);
    const writer = fb.writer();
    try writeBin(writer, "a" ** 1000);
    try std.testing.expectEqualStrings("\x59\x03\xe8" ++ ("a" ** 1000) ++ "\x00", output[0..1004]);
}

test "write CBOR bin 32" {
    var output = [_]u8{0} ** 131072;
    var fb = std.io.fixedBufferStream(&output);
    const writer = fb.writer();
    try writeBin(writer, "a" ** 100000);
    try std.testing.expectEqualStrings("\x5a\x00\x01\x86\xa0" ++ ("a" ** 100000) ++ "\x00", output[0..100006]);
}

test "write CBOR fixarray" {
    var output = [_]u8{0} ** 2;
    var fb = std.io.fixedBufferStream(&output);
    const writer = fb.writer();
    try writeArrayHeader(writer, 1);
    try writeArrayHeader(writer, 0);
    try std.testing.expectEqualStrings("\x81\x80", &output);
}

test "write CBOR array 8" {
    var output = [_]u8{0} ** 2;
    var fb = std.io.fixedBufferStream(&output);
    const writer = fb.writer();
    try writeArrayHeader(writer, 210);
    try std.testing.expectEqualStrings("\x98\xd2", &output);
}

test "write CBOR array 16" {
    var output = [_]u8{0} ** 3;
    var fb = std.io.fixedBufferStream(&output);
    const writer = fb.writer();
    try writeArrayHeader(writer, 1000);
    try std.testing.expectEqualStrings("\x99\x03\xe8", &output);
}

test "write CBOR array 32" {
    var output = [_]u8{0} ** 5;
    var fb = std.io.fixedBufferStream(&output);
    const writer = fb.writer();
    try writeArrayHeader(writer, 100000);
    try std.testing.expectEqualStrings("\x9a\x00\x01\x86\xa0", &output);
}

test "write CBOR array 64" {
    var output = [_]u8{0} ** 9;
    var fb = std.io.fixedBufferStream(&output);
    const writer = fb.writer();
    try writeArrayHeader(writer, 5_000_000_000);
    try std.testing.expectEqualStrings("\x9b\x00\x00\x00\x01\x2A\x05\xF2\x00", &output);
}

test "read fixuint" {
    const v = "\x13";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectEqual(@as(u64, 0x13), try ctx.readU64());
}

test "read u8" {
    const v = "\x18\x88";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectEqual(@as(u64, 0x88), try ctx.readU64());
}

test "read four u8" {
    const v = "\x18\x88\x18\x98\x18\xf4\x18\xaa";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectEqual(@as(u64, 0x88), try ctx.readU64());
    try std.testing.expectEqual(@as(u64, 0x98), try ctx.readU64());
    try std.testing.expectEqual(@as(u64, 0xf4), try ctx.readU64());
    try std.testing.expectEqual(@as(u64, 0xaa), try ctx.readU64());
}

test "read bad u16" {
    const v = "\x19\x19";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectError(Error.MissingBytes, ctx.readU64());
}

test "read u16" {
    const v = "\x19\x19\x84";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectEqual(@as(u64, 0x1984), try ctx.readU64());
}

test "read bad u32" {
    const v = "\x1a\x19\x84";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectError(Error.MissingBytes, ctx.readU64());
}

test "read bad u32 2" {
    const v = "\x1a\x19\x84\x44";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectError(Error.MissingBytes, ctx.readU64());
}

test "read u32" {
    const v = "\x1a\x11\x22\x33\x34";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectEqual(@as(u64, 0x11223334), try ctx.readU64());
}

test "read u64" {
    const v = "\x1b\x11\x22\x33\x34\x45\x56\x67\x78";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectEqual(@as(u64, 0x1122333445566778), try ctx.readU64());
}

test "read fixint" {
    const v = "\x21";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectEqual(@as(i64, -2), try ctx.readI64());
}

test "read bin 0" {
    const v = "\x40";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectEqualStrings("", try ctx.readBin());
}

test "read bad str utf8" {
    const v = "\x62\xc3\x28";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectError(Error.InvalidString, ctx.readStr());
}

test "read fixstr" {
    const v = "\x62hi";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectEqualStrings("hi", try ctx.readStr());
}

test "read str 100" {
    const v = "\x78\x64" ++ "a" ** 100;
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectEqualStrings("a" ** 100, try ctx.readStr());
}


test "read bad bin 1" {
    const v = "\x41";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectError(Error.MissingBytes, ctx.readBin());
}

test "read bin 1" {
    const v = "\x41a";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectEqualStrings("a", try ctx.readBin());
}

test "read bin 100" {
    const v = "\x58\x64" ++ "a" ** 100;
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectEqualStrings("a" ** 100, try ctx.readBin());
}

test "read bin 16bit" {
    const v = "\x59\x03\xe8" ++ ("a" ** 1000);
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectEqualStrings("a" ** 1000, try ctx.readBin());

}

test "read bin 32bit" {
    const v = "\x5a\x00\x01\x86\xa0" ++ ("a" ** 100000);
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectEqualStrings("a" ** 100000, try ctx.readBin());
}

test "read bin 64bit just 1" {
    const v = "\x5b\x00\x00\x00\x00\x00\x00\x00\x01a";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectEqualStrings("a", try ctx.readBin());
}

test "read bad fixarray" {
    const v = "\x81";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    try std.testing.expectEqual(AnyValue{ .array = 1 }, try ctx.readAny());
    try std.testing.expectError(Error.MissingBytes, ctx.readBin());
}

test "read fixarray" {
    const v = "\x81\x01";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    var arr = try ctx.readArray();
    try std.testing.expectError(Error.UnreadItemsInSequence, ctx.readI64());
    try std.testing.expectEqual(@as(i64, 1), try arr.readI64());
    try std.testing.expectError(Error.NoMoreData, arr.readI64());
    try std.testing.expectError(Error.MissingBytes, ctx.readI64());
}

test "read fixarray 2" {
    const v = "\x82\x01\x03";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    var arr = try ctx.readArray();
    try std.testing.expectError(Error.UnreadItemsInSequence, ctx.readI64());
    try std.testing.expectEqual(@as(i64, 1), try arr.readI64());
    try std.testing.expectEqual(@as(i64, 3), try arr.readI64());
    try std.testing.expectError(Error.NoMoreData, arr.readI64());
    try std.testing.expectError(Error.MissingBytes, ctx.readI64());
}

test "read array 100" {
    const v = "\x98\x64" ++ ("\x07" ** 100) ++ "\x02";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    var arr = try ctx.readArray();
    try std.testing.expectError(Error.UnreadItemsInSequence, ctx.readI64());
    for (0..100) |_| {
        try std.testing.expectEqual(@as(i64, 7), try arr.readI64());
    }
    try std.testing.expectError(Error.NoMoreData, arr.readI64());
    try std.testing.expectEqual(@as(i64, 2), try ctx.readI64());
    try std.testing.expectError(Error.MissingBytes, ctx.readI64());
}

test "read array 1000" {
    const v = "\x99\x03\xe8" ++ ("\x07" ** 1000) ++ "\x02";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    var arr = try ctx.readArray();
    try std.testing.expectError(Error.UnreadItemsInSequence, ctx.readI64());
    for (0..1000) |_| {
        try std.testing.expectEqual(@as(i64, 7), try arr.readI64());
    }
    try std.testing.expectError(Error.NoMoreData, arr.readI64());
    try std.testing.expectEqual(@as(i64, 2), try ctx.readI64());
    try std.testing.expectError(Error.MissingBytes, ctx.readI64());
}

test "read array 100000" {
    const v = "\x9a\x00\x01\x86\xa0" ++ ("\x07" ** 100000) ++ "\x02";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    var arr = try ctx.readArray();
    try std.testing.expectError(Error.UnreadItemsInSequence, ctx.readI64());
    for (0..100000) |_| {
        try std.testing.expectEqual(@as(i64, 7), try arr.readI64());
    }
    try std.testing.expectError(Error.NoMoreData, arr.readI64());
    try std.testing.expectEqual(@as(i64, 2), try ctx.readI64());
    try std.testing.expectError(Error.MissingBytes, ctx.readI64());
}

test "read array 64bit just 1" {
    const v = "\x9b\x00\x00\x00\x00\x00\x00\x00\x01\x07\x02";
    var scanner = Scanner{};
    var ctx = scanner.begin(v);
    var arr = try ctx.readArray();
    try std.testing.expectError(Error.UnreadItemsInSequence, ctx.readI64());
    try std.testing.expectEqual(@as(i64, 7), try arr.readI64());
    try std.testing.expectError(Error.NoMoreData, arr.readI64());
    try std.testing.expectEqual(@as(i64, 2), try ctx.readI64());
    try std.testing.expectError(Error.MissingBytes, ctx.readI64());
}

