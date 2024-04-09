const std = @import("std");

// TODO
//  - [ ] mul() overflow check
//  - [ ] div() overflow check
//  - [X] integerPart() test
//  - [X] fractionalPart() test
//  - [X] fromInt() test
//  - [x] eq()
//  - [x] ne()
//  - [x] lt()
//  - [x] le()
//  - [x] gt()
//  - [x] ge()
//  - [X] truncated division

/// The preferred fixed point type.
pub const F32 = F(16, 16);

/// Fixed point number with custom bit sizes.
/// Use exactly 32 bits for optimal performance.
pub fn F(comptime integer_bits: comptime_int, comptime fractional_bits: comptime_int) type {
    // This is the type of the backing integer of the fixed point type.
    const BackingInteger = std.meta.Int(.signed, integer_bits + fractional_bits);

    return packed struct(BackingInteger) {
        const Self = @This();

        // Used by vectors.
        pub const Template = F;
        pub const integer_bit_count = integer_bits;
        pub const fractional_bit_count = fractional_bits;

        // This is used for casting between fixed point representations.
        pub const Fixed = BackingInteger;

        // This is used for casting when performing certain operations.
        pub const LargeFixed = if ((integer_bits + fractional_bits) % 8 == 0) std.meta.Int(.signed, 2 * (integer_bits + fractional_bits)) else std.meta.Int(.signed, 1 + integer_bits + fractional_bits);

        // Masks used for isolating the integer and fractional parts of a fixed point number.
        pub const Mask = std.meta.Int(.unsigned, integer_bits + fractional_bits);
        pub const integer_mask: Mask = ((1 << integer_bits) - 1) << fractional_bits;
        pub const fractional_mask: Mask = ((1 << fractional_bits) - 1);

        // This is used for casting when performing certain operations.
        // It represents integer part of the fixed point value.
        pub const Int = std.meta.Int(.signed, integer_bits);

        // This is used to guarantee that the number of digits in the fixed point
        // value is always less than or equal to the number of significant digits
        // in its float representation, thereby guaranteeing conversion precision.
        pub const Float = std.meta.Float(switch (integer_bits + fractional_bits) {
            0...10 => 16,
            11...24 => 32,
            25...50 => 64,
            51...113 => 128,
            else => @compileError("Unable to represent fixed point value exactly with floating point value"),
        });

        pub usingnamespace if (integer_bits >= 2) struct {
            pub const one = Self{ .bits = 1 << fractional_bits };
        } else struct {};

        pub const max_int = switch (@as(Fixed, std.math.maxInt(Int))) {
            inline 0 => 0,
            inline else => |max| max << fractional_bits,
        };

        pub const min_int = switch (@as(Fixed, std.math.minInt(Int))) {
            inline 0 => 0,
            inline else => |min| min << fractional_bits,
        };

        bits: Fixed = 0,

        /// Initializes a fixed point value from a fraction.
        pub inline fn init(numerator: anytype, denominator: anytype) Self {
            const Numerator = @TypeOf(numerator);
            const Denominator = @TypeOf(numerator);
            const numerator_info = @typeInfo(Numerator);
            const denominator_info = @typeInfo(Denominator);

            const n = if (numerator_info == .Int or numerator_info == .ComptimeInt) blk: {
                break :blk intToFixed(numerator);
            } else {
                @compileError("Expected type " ++ @typeName(Fixed) ++ ", but got type " ++ @typeName(Numerator));
            };

            const d = if (denominator_info == .Int or denominator_info == .ComptimeInt) blk: {
                break :blk @as(Fixed, denominator);
            } else {
                @compileError("Expected type " ++ @typeName(Fixed) ++ ", but got type " ++ @typeName(Denominator));
            };

            return @bitCast(@divTrunc(n, d));
        }

        /// Returns the sum of two fixed point numbers.
        pub inline fn add(augend: Self, addend: anytype) Self {
            return @bitCast(augend.bits + infer(addend));
        }

        /// Returns the difference of two fixed point numbers.
        pub inline fn sub(minuend: Self, subtrahend: anytype) Self {
            return @bitCast(minuend.bits - infer(subtrahend));
        }

        /// Returns the product of two fixed point numbers.
        pub inline fn mul(multiplicand: Self, multiplier: anytype) Self {
            const Type = @TypeOf(multiplier);
            const info = @typeInfo(Type);

            if (Type == Self) {
                return @bitCast(@as(Fixed, @truncate((@as(LargeFixed, multiplicand.bits) * @as(LargeFixed, multiplier.bits)) >> fractional_bits)));
            }

            if (info == .Int or info == .ComptimeInt) {
                return @bitCast(multiplicand.bits * @as(Fixed, multiplier));
            }

            @compileError("Expected type " ++ @typeName(Self) ++ " or " ++ @typeName(Fixed) ++ ", but got type " ++ @typeName(Type));
        }

        /// Returns the quotient of two fixed point numbers.
        pub inline fn div(dividend: Self, divisor: anytype) Self {
            const Type = @TypeOf(divisor);
            const info = @typeInfo(Type);

            if (Type == Self) {
                return @bitCast(@as(Fixed, @truncate(@divTrunc(@as(LargeFixed, dividend.bits) << fractional_bits, @as(LargeFixed, divisor.bits)))));
            }

            if (info == .Int or info == .ComptimeInt) {
                return @bitCast(@divTrunc(dividend.bits, @as(Fixed, divisor)));
            }

            @compileError("Expected type " ++ @typeName(Self) ++ " or " ++ @typeName(Fixed) ++ ", but got type " ++ @typeName(Type));
        }

        /// Returns the integer square of a fixed point number.
        pub inline fn sqr(self: Self) Self {
            return self.mul(self);
        }

        /// Returns the integer power of a fixed point number.
        pub inline fn pow(self: Self, n: anytype) Self {
            return self.rep(self, .mul, n);
        }

        /// Repeats an operation multiple times.
        pub inline fn rep(self: Self, operand: anytype, comptime op: enum { add, sub, mul, div }, n: anytype) Self {
            const Type = @TypeOf(n);
            const info = @typeInfo(Type);

            var result = self;

            switch (info) {
                inline .Int => for (0..n) |_| {
                    result = switch (op) {
                        inline .add => result.add(operand),
                        inline .sub => result.sub(operand),
                        inline .mul => result.mul(operand),
                        inline .div => result.div(operand),
                    };
                },
                inline .ComptimeInt => inline for (0..n) |_| {
                    result = switch (op) {
                        inline .add => result.add(operand),
                        inline .sub => result.sub(operand),
                        inline .mul => result.mul(operand),
                        inline .div => result.div(operand),
                    };
                },
                inline else => @compileError("Expected n to be an integer, but got " ++ @typeName(@TypeOf(n))),
            }

            return result;
        }

        /// Returns the absoulute value of a fixed point number.
        pub inline fn abs(self: Self) Self {
            return @bitCast(@as(Fixed, @intCast(@abs(self.bits))));
        }

        /// Source: Jonathan Hallström.
        /// Returns the square root of a fixed point number.
        pub inline fn sqrt(self: Self) Self {
            // std.debug.assert(self.bits >= 0);
            // @setFloatMode(.Optimized);

            const n = @as(LargeFixed, self.bits) << fractional_bits;

            var x: Fixed = fromFloat(@sqrt(toFloat(self))).bits + 1;

            if (@as(LargeFixed, x) * @as(LargeFixed, x) > n) x -= 1;
            if (@as(LargeFixed, x + 1) * @as(LargeFixed, x + 1) <= n) x += 1;

            return Self{ .bits = x };
        }

        /// Compares two fixed point numbers.
        pub inline fn cmp(a: Self, b: anytype, comptime op: enum { eq, ne, gt, ge, lt, le }) bool {
            return switch (op) {
                .eq => a.bits == infer(b),
                .ne => a.bits != infer(b),
                .gt => a.bits > infer(b),
                .ge => a.bits >= infer(b),
                .lt => a.bits < infer(b),
                .le => a.bits <= infer(b),
            };
        }

        /// Returns the floating point representation of a fixed point number.
        /// Should not be used in logic unless discarding imprecisions deterministically.
        pub inline fn toFloat(self: Self) Float {
            return @as(Float, @floatFromInt(self.bits)) / (1 << fractional_bits);
        }

        /// Returns the fixed point representation of a floating point number.
        inline fn fromFloat(float: Float) Self {
            return @bitCast(@as(Fixed, @intFromFloat(float * (1 << fractional_bits))));
        }

        /// Lossy cast to integer.
        pub inline fn toInt(self: Self) Int {
            if (integer_bits == 0) return 0;
            return @truncate(self.bits >> fractional_bits);
        }

        /// Returns the fixed point representation of an integer.
        pub inline fn fromInt(int: Int) Self {
            if (integer_bits == 0) return Self{};
            return @bitCast(@as(Fixed, int) << fractional_bits);
        }

        /// Returns the integer part of a fixed point number.
        /// TODO: Improve performance.
        pub inline fn integerPart(self: Self) Self {
            if (integer_bits == 0) return Self{};

            const bits: Mask = @bitCast(self.bits);
            const integer_part: Fixed = @bitCast(bits & integer_mask);

            const fractional = (@as(Mask, @bitCast(self)) & fractional_mask) != 0;
            const negative = self.bits < 0;
            const correction = @as(Fixed, @intFromBool(fractional and negative)) << fractional_bits;

            return @bitCast(integer_part + correction);
        }

        /// Returns the fractional part of a fixed point number.
        /// TODO: Make it not depend on integerPart().
        pub inline fn fractionalPart(self: Self) Self {
            if (fractional_bits == 0) return Self{};
            return self.sub(self.integerPart());

            // const bits: Mask = @bitCast(self.bits);
            // const fractional_part: Self = @bitCast(bits & fractional_mask);
            // const negative: Int = @intFromBool(self.bits < 0);
            // const sign = (@as(Fixed, negative) << 2) - 1;
        }

        /// Converts a fixed point number to a different fixed point representation.
        pub inline fn cast(self: Self, comptime new_integer_bits: u16, comptime new_fractional_bits: u16, comptime safety: enum { Safe, Unsafe }) F(new_integer_bits, new_fractional_bits) {
            const Other = F(new_integer_bits, new_fractional_bits);

            if (safety == .Safe and (integer_bits > new_integer_bits or fractional_bits > new_fractional_bits)) {
                @compileError("Unsafe cast from " ++ @typeName(Self) ++ " to " ++ @typeName(Other));
            }

            if (integer_bits + fractional_bits < new_integer_bits + new_fractional_bits) {
                if (fractional_bits > new_fractional_bits) {
                    return @bitCast(@as(Other.Fixed, @intCast(self.bits >> (fractional_bits - new_fractional_bits))));
                } else {
                    return @bitCast(@as(Other.Fixed, @intCast(self.bits)) << (new_fractional_bits - fractional_bits));
                }
            } else {
                if (fractional_bits > new_fractional_bits) {
                    return @bitCast(@as(Other.Fixed, @truncate(self.bits >> (fractional_bits - new_fractional_bits))));
                } else {
                    return @bitCast(@as(Other.Fixed, @truncate(self.bits)) << (new_fractional_bits - fractional_bits));
                }
            }
        }

        /// Safely casts an integer to its fixed point representation.
        pub inline fn intToFixed(int: anytype) Fixed {
            if (integer_bits == 0) return 0;
            return @as(Fixed, @as(Int, int)) << fractional_bits;
        }

        /// Safely casts a value to its fixed point representation.
        pub inline fn infer(value: anytype) Fixed {
            const Type = @TypeOf(value);
            const info = @typeInfo(Type);

            if (Type == Self) {
                return value.bits;
            }

            switch (info) {
                inline .Int, .ComptimeInt => return intToFixed(value),
                else => @compileError("Expected type " ++ @typeName(Self) ++ " or " ++ @typeName(Fixed) ++ ", but got type " ++ @typeName(Type)),
            }
        }
    };
}

// Source: Jonathan Hallström
test "sqrt" {
    const FixedType = F(16, 16);

    for (0..1920) |i| {
        const f = @as(f64, @floatFromInt(i));
        const correct_val = FixedType.fromFloat(@sqrt(f));
        const computed_val = FixedType.fromFloat(f).sqrt();
        try std.testing.expectEqual(correct_val.bits, computed_val.bits);
    }

    const utils = struct {
        fn square(x: anytype) u128 {
            return @as(u128, @intCast(x)) * @as(u128, @intCast(x));
        }

        fn shift(x: anytype, amt: u7) u128 {
            return @as(u128, @intCast(x)) << amt;
        }
    };

    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();
    for (0..100_000) |_| {
        const f = rand.float(f64) * (1920);
        const computed_val = FixedType.fromFloat(f).sqrt();

        var correct_val = FixedType.fromFloat(@sqrt(f));

        while (utils.square(correct_val.bits) < utils.shift(FixedType.fromFloat(f).bits, 16))
            correct_val.bits += 1;

        while (utils.square(correct_val.bits) > utils.shift(FixedType.fromFloat(f).bits, 16))
            correct_val.bits -= 1;

        try std.testing.expectEqual(correct_val.bits, computed_val.bits);
    }
}

test "sqrt_predictability" {
    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();

    const F24_8 = F(24, 8);

    for (0..std.math.maxInt(F24_8.Int)) |i| {
        const f1 = @as(F24_8.Float, @floatFromInt(i));
        const f2 = @as(F24_8.Float, @floatFromInt(i)) + rand.float(F24_8.Float) * 0.001;
        const a = F24_8.fromFloat(f1).sqrt();
        const b = F24_8.fromFloat(f2).sqrt();
        try std.testing.expectEqual(a.bits, b.bits);
    }

    const F16_16 = F(16, 16);

    for (0..std.math.maxInt(F16_16.Int)) |i| {
        const f1 = @as(F16_16.Float, @floatFromInt(i));
        const f2 = @as(F16_16.Float, @floatFromInt(i)) + rand.float(F16_16.Float) * 0.00001;
        const a = F16_16.fromFloat(f1).sqrt();
        const b = F16_16.fromFloat(f2).sqrt();
        try std.testing.expectEqual(a.bits, b.bits);
    }

    const F8_24 = F(8, 24);

    for (0..std.math.maxInt(F8_24.Int)) |i| {
        const f1 = @as(F8_24.Float, @floatFromInt(i));
        const f2 = @as(F8_24.Float, @floatFromInt(i)) + rand.float(F8_24.Float) * 0.00000001;
        const a = F8_24.fromFloat(f1).sqrt();
        const b = F8_24.fromFloat(f2).sqrt();
        try std.testing.expectEqual(a.bits, b.bits);
    }
}

test "cast" {
    const from = 16;
    const safe = 32;
    const unsafe = 8;

    for (0..std.math.maxInt(i8)) |i| {
        const x = F(from, from).init(@as(i8, @intCast(i)), @as(i8, @intCast(std.math.maxInt(i8) - i)));

        const safe_bits = x.cast(safe, safe, .Safe);
        const unsafe_integer_bits = x.cast(unsafe, safe, .Unsafe);
        const unsafe_fractional_bits = x.cast(safe, unsafe, .Unsafe);
        const unsafe_bits = x.cast(unsafe, unsafe, .Unsafe);

        try std.testing.expectEqual(x.toInt(), safe_bits.toInt());
        try std.testing.expectEqual(x.toInt(), unsafe_integer_bits.toInt());
        try std.testing.expectEqual(x.toInt(), unsafe_fractional_bits.toInt());
        try std.testing.expectEqual(x.toInt(), unsafe_bits.toInt());
    }

    inline for (1..unsafe) |i| {
        const x = F(from, from).init(1, 1 << @as(u8, @intCast(i)));
        const safe_cast = x.cast(safe, safe, .Safe);
        const unsafe_cast = safe_cast.cast(unsafe, unsafe, .Unsafe);
        const y = unsafe_cast.cast(from, from, .Safe);

        try std.testing.expectEqual(x.bits, y.bits);
    }
}

test "arithmetic" {
    const eq = std.testing.expectEqual;

    for (1..100) |i| {
        const j: i16 = @intCast(i);
        const f = F32.init(j, 1);

        try eq(j + j, f.add(j).toInt());
        try eq(j + j, f.add(f).toInt());
        try eq(j - j, f.sub(j).toInt());
        try eq(j - j, f.sub(f).toInt());
        try eq(j * j, f.mul(j).toInt());
        try eq(j * j, f.mul(f).toInt());
        try eq(@divTrunc(j, j), f.div(j).toInt());
        try eq(@divTrunc(j, j), f.div(f).toInt());
    }
}

test "from_integer" {
    const max_bits = 113;
    inline for (2..max_bits + 1) |i| {
        const FX = F(i, max_bits - i);
        try std.testing.expectEqual(FX.fromInt(i - 1), FX.init(i - 1, 1));
    }
}

test "one" {
    const max_bits = 113;
    inline for (2..max_bits + 1) |i| {
        const FX = F(i, max_bits - i);
        try std.testing.expectEqual(FX.fromInt(1), FX.one);
    }
}

test "integer_part" {
    const eq = std.testing.expectEqual;
    const max_bits = 64;

    try eq(0, (F(0, max_bits){}).integerPart().bits);
    try eq(0, (F(1, max_bits - 1){}).integerPart().bits);

    inline for (2..max_bits + 1) |i| {
        const FX = F(i, max_bits - i);
        const max_int = @min(std.math.maxInt(FX.Int), 5000);
        const min_int = @max(std.math.minInt(FX.Int), -5000);

        var j: isize = min_int;
        while (j < max_int) : (j += 1) {
            const k: FX.Int = @intCast(j);

            const expected = FX.fromInt(@divTrunc(k, max_int));
            const computed = FX.init(k, max_int).integerPart();

            try eq(expected, computed);
        }
    }
}

test "fractional_part" {
    @setEvalBranchQuota(2000);
    const eq = std.testing.expectEqual;
    const max_bits = 64;

    inline for (2..max_bits + 1) |i| {
        const FX = F(i, max_bits - i);
        const max_int = @min(std.math.maxInt(FX.Int), 5000);
        const min_int = @max(std.math.minInt(FX.Int), -5000);

        var j: isize = min_int;
        while (j < max_int) : (j += 1) {
            const k: FX.Int = @intCast(j);

            const tmp = FX.init(k, max_int);
            const expected = tmp.sub(tmp.integerPart());
            const computed = tmp.fractionalPart();

            try eq(expected, computed);
        }
    }
}

test "comparisons" {
    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();
    for (0..100_000) |_| {
        const r1 = rand.int(i15);
        const r2 = rand.int(i15);
        const f = F32.init(r1, if (r2 != 0) r2 else 1);
        const g = f.add(1);
        const l = f.sub(1);

        try std.testing.expect(f.cmp(f, .eq));
        try std.testing.expect(!f.cmp(f, .ne));
        try std.testing.expect(!f.cmp(f, .gt));
        try std.testing.expect(f.cmp(f, .ge));
        try std.testing.expect(!f.cmp(f, .lt));
        try std.testing.expect(f.cmp(f, .le));

        try std.testing.expect(!f.cmp(g, .eq));
        try std.testing.expect(f.cmp(g, .ne));
        try std.testing.expect(!f.cmp(g, .gt));
        try std.testing.expect(!f.cmp(g, .ge));
        try std.testing.expect(f.cmp(g, .lt));
        try std.testing.expect(f.cmp(g, .le));

        try std.testing.expect(!f.cmp(l, .eq));
        try std.testing.expect(f.cmp(l, .ne));
        try std.testing.expect(f.cmp(l, .gt));
        try std.testing.expect(f.cmp(l, .ge));
        try std.testing.expect(!f.cmp(l, .lt));
        try std.testing.expect(!f.cmp(l, .le));
    }
}

test "extreme_values" {
    const maxInt = std.math.maxInt;
    const minInt = std.math.minInt;
    const Int = std.meta.Int;
    const eq = std.testing.expectEqual;
    const max_bits = 64;
    inline for (0..max_bits + 1) |i| {
        const FX = F(i, max_bits - i);

        const expected_max = maxInt(Int(.signed, i));
        const expected_min = minInt(Int(.signed, i));

        const computed_max = (FX{ .bits = FX.max_int }).toInt();
        const computed_min = (FX{ .bits = FX.min_int }).toInt();

        try eq(expected_max, computed_max);
        try eq(expected_min, computed_min);
    }
}

test "repetition" {
    const one = F(16, 16).one;

    try std.testing.expectEqual(one.mul(16), one.rep(2, .mul, 4));
    try std.testing.expectEqual(one.bits << 10, one.rep(2, .mul, 10).bits);

    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();
    for (0..100_000) |_| {
        const n: u8 = rand.int(u8);

        var expected = one;
        for (0..n) |_| {
            expected = expected.add(one);
        }

        const computed = one.rep(1, .add, n);

        try std.testing.expectEqual(expected, computed);
    }
}
