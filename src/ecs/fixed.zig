const std = @import("std");

/// Fixed point number with custom bit size.
/// Use exactly 32 bits for optimal performance.
pub fn F(comptime integer_bits: u16, comptime fractional_bits: u16) type {
    // This is the type of the backing integer for the fixed point type.
    const Fixed = std.meta.Int(.signed, integer_bits + fractional_bits);

    // This is used for casting when performing certain operations.
    const LargeFixed = if ((integer_bits + fractional_bits) % 8 == 0) std.meta.Int(.signed, 2 * (integer_bits + fractional_bits)) else std.meta.Int(.signed, 1 + integer_bits + fractional_bits);

    // This is used for casting when performing certain operations.
    const Int = std.meta.Int(.signed, integer_bits);

    // This is used to guarantee that the number of digits in the fixed point
    // value is always less than or equal to the number of significant digits
    // in its float representation, thereby guaranteeing conversion precision.
    const Float = std.meta.Float(switch (integer_bits + fractional_bits) {
        0...10 => 16,
        11...24 => 32,
        25...50 => 64,
        51...113 => 128,
        else => @compileError("Invalid bit size"),
    });

    return packed struct(Fixed) {
        const Self = @This();
        const Cast = Fixed;

        bits: Fixed = 0,

        /// Initializes a fixed point value from a fraction.
        pub inline fn init(numerator: anytype, denominator: anytype) Self {
            const Numerator = @TypeOf(numerator);
            const Denominator = @TypeOf(numerator);
            const numerator_info = @typeInfo(Numerator);
            const denominator_info = @typeInfo(Denominator);

            const n = if (numerator_info == .Int or numerator_info == .ComptimeInt) blk: {
                break :blk fixedFromInt(numerator);
            } else {
                @compileError("Expected type " ++ @typeName(Fixed) ++ ", but got type " ++ @typeName(Numerator));
            };

            const d = if (denominator_info == .Int or denominator_info == .ComptimeInt) blk: {
                break :blk @as(Fixed, denominator);
            } else {
                @compileError("Expected type " ++ @typeName(Fixed) ++ ", but got type " ++ @typeName(Denominator));
            };

            return @bitCast(@divFloor(n, d));
        }

        /// Returns the sum of two fixed point numbers.
        pub inline fn add(augend: Self, addend: anytype) Self {
            const Type = @TypeOf(addend);
            const info = @typeInfo(Type);

            if (Type == Self) {
                return @bitCast(augend.bits + addend.bits);
            }

            if (info == .Int or info == .ComptimeInt) {
                return @bitCast(augend.bits + fixedFromInt(addend));
            }

            @compileError("Expected type " ++ @typeName(Self) ++ " or " ++ @typeName(Fixed) ++ ", but got type " ++ @typeName(Type));
        }

        /// Returns the difference of two fixed point numbers.
        pub inline fn sub(minuend: Self, subtrahend: anytype) Self {
            const Type = @TypeOf(subtrahend);
            const info = @typeInfo(Type);

            if (Type == Self) {
                return @bitCast(minuend.bits - subtrahend.bits);
            }

            if (info == .Int or info == .ComptimeInt) {
                return @bitCast(minuend.bits - fixedFromInt(subtrahend));
            }

            @compileError("Expected type " ++ @typeName(Self) ++ " or " ++ @typeName(Fixed) ++ ", but got type " ++ @typeName(Type));
        }

        /// Returns the product of two fixed point numbers.
        pub inline fn mul(multiplicand: Self, multiplier: anytype) Self {
            const Type = @TypeOf(multiplier);
            const info = @typeInfo(Type);

            if (Type == Self) {
                return @bitCast(@as(Fixed, @truncate((@as(LargeFixed, multiplicand.bits) * @as(LargeFixed, multiplier.bits)) >> fractional_bits)));
            }

            if (info == .Int or info == .ComptimeInt) {
                return @bitCast(@as(Fixed, @truncate((@as(LargeFixed, multiplicand.bits) * @as(LargeFixed, fixedFromInt(multiplier))) >> fractional_bits)));
            }

            @compileError("Expected type " ++ @typeName(Self) ++ " or " ++ @typeName(Fixed) ++ ", but got type " ++ @typeName(Type));
        }

        /// Returns the quotient of two fixed point numbers.
        pub inline fn div(dividend: Self, divisor: anytype) Self {
            const Type = @TypeOf(divisor);
            const info = @typeInfo(Type);

            if (Type == Self) {
                return @bitCast(@as(Fixed, @truncate(@divFloor(@as(LargeFixed, dividend.bits) << fractional_bits, @as(LargeFixed, divisor.bits)))));
            }

            if (info == .Int or info == .ComptimeInt) {
                return @bitCast(@divFloor(dividend.bits, @as(Fixed, divisor)));
            }

            @compileError("Expected type " ++ @typeName(Self) ++ " or " ++ @typeName(Fixed) ++ ", but got type " ++ @typeName(Type));
        }

        /// Returns the absoulute value of a fixed point number.
        pub inline fn abs(self: Self) Self {
            return @bitCast(@as(Fixed, @intCast(@abs(self.bits))));
        }

        /// Source: Jonathan Hallström.
        /// Returns the square root of a fixed point number. Slower than @sqrt().
        pub inline fn sqrt(self: Self) Self {
            // std.debug.assert(self.bits >= 0);
            // @setFloatMode(.Optimized);

            const n = @as(LargeFixed, self.bits) << fractional_bits;

            var x: Fixed = fromFloat(@sqrt(toFloat(self))).bits + 1;

            if (@as(LargeFixed, x) * @as(LargeFixed, x) > n) x -= 1;
            if (@as(LargeFixed, x + 1) * @as(LargeFixed, x + 1) <= n) x += 1;

            return Self{ .bits = x };
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

        /// TODO: Test
        /// Converts a fixed point number to a different fixed point representation.
        pub inline fn cast(self: Self, comptime new_integer_bits: u16, comptime new_fractional_bits: u16, comptime safety: enum { Safe, Unsafe }) F(new_integer_bits, new_fractional_bits) {
            const Other = F(new_integer_bits, new_fractional_bits);

            if (safety == .Safe and (integer_bits > new_integer_bits or fractional_bits > new_fractional_bits)) {
                @compileError("Unsafe cast from " ++ @typeName(Self) ++ " to " ++ @typeName(Other));
            }

            if (integer_bits + fractional_bits < new_integer_bits + new_fractional_bits) {
                if (fractional_bits > new_fractional_bits) {
                    return @bitCast(@as(Other.Cast, @intCast(self.bits >> (fractional_bits - new_fractional_bits))));
                } else {
                    return @bitCast(@as(Other.Cast, @intCast(self.bits)) << (new_fractional_bits - fractional_bits));
                }
            } else {
                if (fractional_bits > new_fractional_bits) {
                    return @bitCast(@as(Other.Cast, @truncate(self.bits >> (fractional_bits - new_fractional_bits))));
                } else {
                    return @bitCast(@as(Other.Cast, @truncate(self.bits)) << (new_fractional_bits - fractional_bits));
                }
            }
        }

        /// Safely casts an integer to its fixed point representation.
        inline fn fixedFromInt(int: anytype) Fixed {
            return @as(Fixed, @as(Int, int)) << fractional_bits;
        }

        /// Lossy cast to integer.
        pub inline fn toInt(self: Self) Int {
            return @truncate(self.bits >> fractional_bits);
        }
    };
}

// Source: Jonathan Hallström
test "sqrt" {
    const FixedType = F(16, 16);
    for (0..1081) |i| {
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
        const f = rand.float(f64) * (1080);
        const computed_val = FixedType.fromFloat(f).sqrt();

        var correct_val = FixedType.fromFloat(@sqrt(f));

        while (utils.square(correct_val.bits) < utils.shift(FixedType.fromFloat(f).bits, 16))
            correct_val.bits += 1;

        while (utils.square(correct_val.bits) > utils.shift(FixedType.fromFloat(f).bits, 16))
            correct_val.bits -= 1;

        try std.testing.expectEqual(correct_val.bits, computed_val.bits);
    }
}

test "cast" {
    const From = F(16, 16);

    const safe = 32;
    const unsafe = 8;

    for (0..std.math.maxInt(i8)) |i| {
        const x = From.init(@as(i8, @intCast(i)), @as(i8, @intCast(std.math.maxInt(i8) - i)));

        const safe_bits = x.cast(safe, safe, .Safe);
        const unsafe_integer_bits = x.cast(unsafe, safe, .Unsafe);
        const unsafe_fractional_bits = x.cast(safe, unsafe, .Unsafe);
        const unsafe_bits = x.cast(unsafe, unsafe, .Unsafe);

        if (x.toInt() != safe_bits.toInt()) unreachable;
        if (x.toInt() != unsafe_integer_bits.toInt()) unreachable;
        if (x.toInt() != unsafe_fractional_bits.toInt()) unreachable;
        if (x.toInt() != unsafe_bits.toInt()) unreachable;
    }
}
