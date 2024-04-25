const std = @import("std");
const fixed = @import("fixed.zig");

// TODO
//  - [ ] mul() overflow check, fast int version
//  - [ ] div() overflow check, fast int version
//  - [X] lerp() test
//  - [X] proj()
//  - [X] rej()
//  - [X] dist() test
//  - [X] init() refactor
//  - [ ] swizzle()
//  - [X] infer() & refactor
//  - [X] integerParts()
//  - [X] fractionalParts()
//  - [X] toInts()
//  - [X] fromInts()
//  - [ ] fixedCast()
//  - [ ] resizeCast()
//  - [X] min()
//  - [X] max()
//  - [X] eq()
//  - [X] ne()

pub const P = V;
pub fn V(comptime dimensions: comptime_int, comptime F: anytype) type {
    if (dimensions < 2 and 4 < dimensions) {
        @compileError("Number of dimensions must be 2, 3, or 4");
    }

    if (F.Template != fixed.F) {
        @compileError("Expected type of template " ++ @typeName(fixed.F) ++ ", but got type " ++ @typeName(F));
    }

    return struct {
        const Self = @This();
        const Fixed = F;
        const Vector = @Vector(dimensions, F.Fixed);
        const LargeVector = @Vector(dimensions, F.LargeFixed);
        const Mask = @Vector(dimensions, F.Mask);

        vector: Vector = [_]F.Fixed{0} ** dimensions,
        comptime Fixed: type = F,

        pub inline fn fromAny(value: anytype) Self {
            return Self{ .vector = infer(value) };
        }

        pub inline fn i() Self {
            switch (dimensions) {
                inline 2 => return Self.init(1, 0),
                inline 3 => return Self.init(1, 0, 0),
                inline 4 => return Self.init(1, 0, 0, 0),
                inline else => unreachable,
            }
        }

        pub inline fn j() Self {
            switch (dimensions) {
                inline 2 => return Self.init(0, 1),
                inline 3 => return Self.init(0, 1, 0),
                inline 4 => return Self.init(0, 1, 0, 0),
                inline else => unreachable,
            }
        }

        pub inline fn x(self: Self) F {
            return fixedCast(self.vector[0]);
        }

        pub inline fn y(self: Self) F {
            return fixedCast(self.vector[1]);
        }

        pub usingnamespace if (dimensions >= 3) struct {
            pub inline fn z(self: Self) F {
                return fixedCast(self.vector[2]);
            }

            pub inline fn k() Self {
                switch (dimensions) {
                    inline 3 => return Self.init(0, 0, 1),
                    inline 4 => return Self.init(0, 0, 1, 0),
                    inline else => unreachable,
                }
            }
        } else struct {};

        pub usingnamespace if (dimensions == 4) struct {
            pub inline fn w(self: Self) F {
                return fixedCast(self.vector[3]);
            }

            pub inline fn l() Self {
                return Self.init(0, 0, 0, 1);
            }
        } else struct {};

        pub usingnamespace switch (dimensions) {
            inline 2 => struct {
                pub inline fn init(x_init: anytype, y_init: anytype) Self {
                    return Self{ .vector = .{ F.infer(x_init), F.infer(y_init) } };
                }

                pub inline fn cross(self: Self, vec: Self) F {
                    return self.x().mul(vec.y()).sub(self.y().mul(vec.x()));
                }
            },
            inline 3 => struct {
                pub inline fn init(x_init: anytype, y_init: anytype, z_init: anytype) Self {
                    return Self{ .vector = .{ F.infer(x_init), F.infer(y_init), F.infer(z_init) } };
                }

                pub inline fn cross(self: Self, vec: Self) Self {
                    const x_init = self.y().mul(vec.z()).sub(self.z().mul(vec.y()));
                    const y_init = self.z().mul(vec.x()).sub(self.x().mul(vec.z()));
                    const z_init = self.x().mul(vec.y()).sub(self.y().mul(vec.x()));

                    return init(x_init, y_init, z_init);
                }
            },
            inline 4 => struct {
                pub inline fn init(x_init: anytype, y_init: anytype, z_init: anytype, w_init: anytype) Self {
                    return Self{ .vector = .{ F.infer(x_init), F.infer(y_init), F.infer(z_init), F.infer(w_init) } };
                }
            },
            inline else => unreachable,
        };

        /// Sets self to value.
        pub inline fn set(self: *Self, value: anytype) void {
            self.vector = infer(value);
        }

        /// Performs elementwise addition.
        pub inline fn add(augend: Self, addend: anytype) Self {
            return Self{ .vector = augend.vector + infer(addend) };
        }

        /// Performs elementwise subtraction.
        pub inline fn sub(minuend: Self, subtrahend: anytype) Self {
            return Self{ .vector = minuend.vector - infer(subtrahend) };
        }

        /// Performs elementwise division.
        pub inline fn mul(multiplicand: Self, multiplier: anytype) Self {
            return Self{ .vector = @as(Vector, @truncate((@as(LargeVector, multiplicand.vector) * @as(LargeVector, infer(multiplier))) >> @splat(F.fractional_bit_count))) };
        }

        /// Performs elementwise division.
        pub inline fn div(dividend: Self, divisor: anytype) Self {
            const n = @as(LargeVector, dividend.vector) << @splat(F.fractional_bit_count);
            const d = @as(LargeVector, infer(divisor));
            const v = @divTrunc(n, d);

            return Self{ .vector = @truncate(v) };
        }

        /// Performs the absolute value function elementwise.
        pub inline fn abs(self: Self) Self {
            return Self{ .vector = @intCast(@abs(self.vector)) };
        }

        /// Returns a fixed point number representing the largest element,
        /// the smallest element, or the sum of all elements.
        pub inline fn reduce(self: Self, comptime op: std.builtin.ReduceOp) F {
            switch (op) {
                .Add => return fixedCast(@reduce(.Add, self.vector)),
                .Max => return fixedCast(@reduce(.Max, self.vector)),
                .Min => return fixedCast(@reduce(.Min, self.vector)),
                else => @compileError("Operation not supported"),
            }
        }

        /// Compares two vectors for inequality.
        pub inline fn eq(a: Self, b: Self) bool {
            return @reduce(std.builtin.ReduceOp.And, a.vector == b.vector);
        }

        /// Compares two vectors for inequality.
        pub inline fn ne(a: Self, b: Self) bool {
            return @reduce(std.builtin.ReduceOp.Or, a.vector != b.vector);
        }

        /// Returns the squared magnitude of a vector.
        pub inline fn mag2(self: Self) F {
            return self.mul(self).reduce(.Add);
        }

        /// Returns the magnitude of a vector.
        pub inline fn mag(self: Self) F {
            return self.mag2().sqrt();
        }

        /// returns the dot product of two vectors.
        pub inline fn dot(self: Self, vec: Self) F {
            return self.mul(vec).reduce(.Add);
        }

        /// Returns the additive inverse of a vector.
        pub inline fn neg(self: Self) Self {
            return self.mul(-1);
        }

        /// Linear interpolation
        pub inline fn lerp(from: Self, to: Self, t: anytype) Self {
            return to.sub(from).mul(t).add(from);
        }

        /// Orthogonal projection.
        pub inline fn proj(self: Self, onto: Self) Self {
            return onto.mul(self.dot(onto).div(mag2(onto)));
        }

        /// Orthogonal rejection.
        pub inline fn rej(self: Self, onto: Self) Self {
            return self.sub(self.proj(onto));
        }

        /// Returns the squared distance between two points.
        pub inline fn dist2(from: Self, to: Self) F {
            return to.sub(from).mag2();
        }

        /// Returns the distance between two points.
        pub inline fn dist(from: Self, to: Self) F {
            return dist2(from, to).sqrt();
        }

        /// Lossy cast to integer vector.
        /// The returned value is floored.
        pub inline fn toInts(self: Self) @Vector(dimensions, F.Int) {
            return @truncate(self.vector >> @splat(F.fractional_bit_count));
        }

        /// Returns the fixed point representation vector of an integer vector or integer array.
        pub inline fn fromInts(ints: @Vector(dimensions, F.Int)) Self {
            return Self{ .vector = @as(@Vector(dimensions, F.Fixed), ints) << @splat(F.fractional_bit_count) };
        }

        pub inline fn integerParts(self: Self) Self {
            if (F.integer_bit_count == 0) return Self{};

            const bits: Mask = @bitCast(self.vector);
            const integer_mask: Mask = @splat(F.integer_mask);
            const integer_parts: Vector = @bitCast(bits & integer_mask);

            const zeroes_mask: Mask = @splat(0);
            const zeroes_vector: Vector = @splat(0);
            const fractional_mask: Mask = @splat(F.fractional_mask);
            const fractionals: Vector = @intFromBool((@as(Mask, @bitCast(self.vector)) & fractional_mask) != zeroes_mask);
            const negatives: Vector = @intFromBool(self.vector < zeroes_vector);
            const correction = (fractionals & negatives) << @splat(F.fractional_bit_count);

            return Self{ .vector = @bitCast(integer_parts + correction) };
        }

        pub inline fn fractionalParts(self: Self) Self {
            if (F.fractional_bit_count == 0) return Self{};
            return self.sub(self.integerParts());

            // const bits: @Vector(dimensions, F.Mask) = @bitCast(self.vector);
            // const mask: @Vector(dimensions, F.Mask) = @splat(F.fractional_mask);

            // return Self{ .vector = @bitCast(bits & mask) };
        }

        inline fn intsToVector(ints: anytype) Vector {
            return @as(Vector, @as(@Vector(dimensions, F.Int), ints)) << @splat(F.fractional_bit_count);
        }

        inline fn infer(value: anytype) Vector {
            const Type = @TypeOf(value);
            const info = @typeInfo(Type);

            if (Type == Self) {
                return value.vector;
            }

            switch (info) {
                inline .Array, .Vector => |vector| {
                    if (vector.child == F) {
                        return value;
                    }

                    switch (@typeInfo(vector.child)) {
                        inline .Int, .ComptimeInt => return intsToVector(value),
                        inline else => @compileError("Expected type Int or ComptimeInt, but got type " ++ @typeName(Type)),
                    }
                },
                inline else => return @splat(F.infer(value)),
            }
        }

        inline fn fixedCast(f: F.Fixed) F {
            return @bitCast(f);
        }
    };
}

test "initialization" {
    const F16_16 = fixed.F(16, 16);

    for (0..std.math.maxInt(F16_16.Int)) |i| {
        const j: i16 = @intCast(i);

        const vec2 = V(2, F16_16).init(j, j);
        const vec3 = V(3, F16_16).init(j, j, j);
        const vec4 = V(4, F16_16).init(j, j, j, j);

        const x = F16_16.intToFixed(j);

        try std.testing.expect(vec2.x().bits == x);
        try std.testing.expect(vec2.y().bits == x);

        try std.testing.expect(vec3.x().bits == x);
        try std.testing.expect(vec3.y().bits == x);
        try std.testing.expect(vec3.z().bits == x);

        try std.testing.expect(vec4.x().bits == x);
        try std.testing.expect(vec4.y().bits == x);
        try std.testing.expect(vec4.z().bits == x);
        try std.testing.expect(vec4.w().bits == x);
    }

    for (0..std.math.maxInt(F16_16.Int)) |i| {
        const int: i16 = @intCast(i);
        const fix = F16_16.init(int, 1);

        const vec2_int = V(2, F16_16).init(int, int);
        const vec3_int = V(3, F16_16).init(int, int, int);
        const vec4_int = V(4, F16_16).init(int, int, int, int);

        const vec2_fix = V(2, F16_16).init(fix, fix);
        const vec3_fix = V(3, F16_16).init(fix, fix, fix);
        const vec4_fix = V(4, F16_16).init(fix, fix, fix, fix);

        try std.testing.expectEqual(vec2_int, vec2_fix);
        try std.testing.expectEqual(vec3_int, vec3_fix);
        try std.testing.expectEqual(vec4_int, vec4_fix);
    }
}

test "cross_product" {
    const F16_16 = fixed.F(16, 16);

    const u_1 = V(2, F16_16).init(-3, 7);
    const u_2 = V(2, F16_16).init(1, 2);

    try std.testing.expect(u_1.cross(u_2).bits == F16_16.init(-13, 1).bits);

    const v_1 = V(3, F16_16).init(6, 7, 4);
    const v_2 = V(3, F16_16).init(5, -2, 1);
    const cross = v_1.cross(v_2);

    try std.testing.expect(cross.x().bits == F16_16.init(15, 1).bits);
    try std.testing.expect(cross.y().bits == F16_16.init(14, 1).bits);
    try std.testing.expect(cross.z().bits == F16_16.init(-47, 1).bits);
}

test "addition" {
    const F16_16 = fixed.F(16, 16);
    const V2_16_16 = V(2, F16_16);

    const u = V2_16_16.init(-3, 7);
    const v = V2_16_16.init(1, 2);
    const int = 10;
    const fix = F16_16.init(4, 1);

    const sum_1 = u.add(v);
    const sum_2 = u.add(int);
    const sum_3 = u.add(fix);

    try std.testing.expectEqual(@Vector(2, F16_16.Fixed){ F16_16.init(-2, 1).bits, F16_16.init(9, 1).bits }, sum_1.vector);
    try std.testing.expectEqual(@Vector(2, F16_16.Fixed){ F16_16.init(7, 1).bits, F16_16.init(17, 1).bits }, sum_2.vector);
    try std.testing.expectEqual(@Vector(2, F16_16.Fixed){ F16_16.init(1, 1).bits, F16_16.init(11, 1).bits }, sum_3.vector);
}

test "subtraction" {
    const F16_16 = fixed.F(16, 16);
    const V2_16_16 = V(2, F16_16);

    const u = V2_16_16.init(-3, 7);
    const v = V2_16_16.init(1, 2);
    const int = 10;
    const fix = F16_16.init(4, 1);

    const difference_1 = u.sub(v);
    const difference_2 = u.sub(int);
    const difference_3 = u.sub(fix);

    try std.testing.expectEqual(@Vector(2, F16_16.Fixed){ F16_16.init(-4, 1).bits, F16_16.init(5, 1).bits }, difference_1.vector);
    try std.testing.expectEqual(@Vector(2, F16_16.Fixed){ F16_16.init(-13, 1).bits, F16_16.init(-3, 1).bits }, difference_2.vector);
    try std.testing.expectEqual(@Vector(2, F16_16.Fixed){ F16_16.init(-7, 1).bits, F16_16.init(3, 1).bits }, difference_3.vector);
}

test "multiplication" {
    const F16_16 = fixed.F(16, 16);
    const V2_16_16 = V(2, F16_16);

    const u = V2_16_16.init(2, -1);
    const v = V2_16_16.init(6, 3);
    const int = 2;
    const fix = F16_16.init(4, 1);

    const product_1 = u.mul(v);
    const product_2 = u.mul(int);
    const product_3 = u.mul(fix);

    try std.testing.expectEqual(@Vector(2, F16_16.Fixed){ F16_16.init(12, 1).bits, F16_16.init(-3, 1).bits }, product_1.vector);
    try std.testing.expectEqual(@Vector(2, F16_16.Fixed){ F16_16.init(4, 1).bits, F16_16.init(-2, 1).bits }, product_2.vector);
    try std.testing.expectEqual(@Vector(2, F16_16.Fixed){ F16_16.init(8, 1).bits, F16_16.init(-4, 1).bits }, product_3.vector);

    const a = V2_16_16.init(3, 4);
    const b = F16_16.init(3, 2);
    const x_expected = b.mul(3).bits;
    const y_extpected = b.mul(4).bits;
    try std.testing.expectEqual(@Vector(2, F16_16.Fixed){ x_expected, y_extpected }, a.mul(b).vector);
}

test "division" {
    const F16_16 = fixed.F(16, 16);
    const V2_16_16 = V(2, F16_16);

    const u = V2_16_16.init(10, -2);
    const v = V2_16_16.init(2, 4);
    const int = 7;
    const fix = F16_16.init(1, 2);

    const quotient_1 = u.div(v);
    const quotient_2 = u.div(int);
    const quotient_3 = u.div(fix);

    try std.testing.expectEqual(@Vector(2, F16_16.Fixed){ F16_16.init(10, 2).bits, F16_16.init(-2, 4).bits }, quotient_1.vector);
    try std.testing.expectEqual(@Vector(2, F16_16.Fixed){ F16_16.init(10, 7).bits, F16_16.init(-2, 7).bits }, quotient_2.vector);
    try std.testing.expectEqual(@Vector(2, F16_16.Fixed){ F16_16.init(20, 1).bits, F16_16.init(-4, 1).bits }, quotient_3.vector);
}

test "vector_sum" {
    const F16_16 = fixed.F(16, 16);
    const u = V(4, F16_16).init(2, -1, 10, -2);
    try std.testing.expectEqual(F16_16.init(9, 1).bits, u.reduce(.Add).bits);

    for (0..std.math.maxInt(F16_16.Int) / 4) |i| {
        const j: i16 = @intCast(i);
        const x = j - 10;
        const y = @divTrunc(j, 3);
        const z = j;
        const w = @divTrunc(j, 2) + 1;
        const v = V(4, F16_16).init(x, y, z, w);
        try std.testing.expectEqual(F16_16.init(x + y + z + w, 1).bits, v.reduce(.Add).bits);
    }
}

test "magnitude_squared" {
    const eq = std.testing.expectEqual;
    const F32 = fixed.F(16, 16);

    const V2 = V(2, F32);
    const V3 = V(3, F32);
    const V4 = V(4, F32);

    for (0..90) |i| {
        const a = F32.init(@as(i16, @intCast(i + 0)), 1);
        const b = F32.init(@as(i16, @intCast(i + 1)), 1);
        const c = F32.init(@as(i16, @intCast(i + 2)), 1);
        const d = F32.init(@as(i16, @intCast(i + 3)), 1);

        const v2_computed = V2.init(a, b).mag2();
        const v2_expected = a.mul(a).add(b.mul(b));
        try eq(v2_expected, v2_computed);

        const v3_computed = V3.init(a, b, c).mag2();
        const v3_expected = a.mul(a).add(b.mul(b)).add(c.mul(c));
        try eq(v3_expected, v3_computed);

        const v4_computed = V4.init(a, b, c, d).mag2();
        const v4_expected = a.mul(a).add(b.mul(b)).add(c.mul(c)).add(d.mul(d));
        try eq(v4_expected, v4_computed);
    }
}

test "magnitude" {
    const eq = std.testing.expectEqual;
    const F32 = fixed.F(16, 16);

    const V2 = V(2, F32);
    const V3 = V(3, F32);
    const V4 = V(4, F32);

    for (0..90) |i| {
        const a = F32.init(@as(i16, @intCast(i + 0)), 1);
        const b = F32.init(@as(i16, @intCast(i + 1)), 1);
        const c = F32.init(@as(i16, @intCast(i + 2)), 1);
        const d = F32.init(@as(i16, @intCast(i + 3)), 1);

        const v2_computed = V2.init(a, b).mag();
        const v2_expected = a.mul(a).add(b.mul(b)).sqrt();
        try eq(v2_expected, v2_computed);

        const v3_computed = V3.init(a, b, c).mag();
        const v3_expected = a.mul(a).add(b.mul(b)).add(c.mul(c)).sqrt();
        try eq(v3_expected, v3_computed);

        const v4_computed = V4.init(a, b, c, d).mag();
        const v4_expected = a.mul(a).add(b.mul(b)).add(c.mul(c)).add(d.mul(d)).sqrt();
        try eq(v4_expected, v4_computed);
    }
}

test "projection" {
    const eq = std.testing.expectEqual;
    const F32 = fixed.F(16, 16);
    const V2 = V(2, F32);

    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();

    try eq(V2{}, V2.i().proj(V2.j()));
    try eq(V2{}, V2.j().proj(V2.i()));

    for (0..100_000) |_| {
        const x = rand.int(i8);
        const y = rand.int(i8);
        const p1 = V2.init(if (x == 0) 1 else x, if (y == 0) 1 else y);

        try eq(p1, V2.proj(p1, p1));
    }
}

test "rejection" {
    const eq = std.testing.expectEqual;
    const F32 = fixed.F(16, 16);
    const V2 = V(2, F32);

    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();

    try eq(V2.i(), V2.i().rej(V2.j()));
    try eq(V2.j(), V2.j().rej(V2.i()));

    for (0..100_000) |_| {
        const x = rand.int(i8);
        const y = rand.int(i8);
        const p = V2.init(if (x == 0) 1 else x, if (y == 0) 1 else y);

        try eq(V2{}, V2.rej(p, p));
    }
}

test "negation" {
    const eq = std.testing.expectEqual;
    const F32 = fixed.F(16, 16);
    const V2 = V(2, F32);

    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();

    for (0..100_000) |_| {
        const x: i16 = rand.int(i8);
        const y: i16 = rand.int(i8);
        try eq(V2.init(x, y).neg(), V2.init(-x, -y));
    }
}

test "comparison" {
    const F32 = fixed.F(16, 16);

    const V2 = V(2, F32);
    const V3 = V(3, F32);
    const V4 = V(4, F32);

    for (0..10000) |i| {
        const a: i16 = @intCast(i + 0);
        const b: i16 = @intCast(i + 1);
        const c: i16 = @intCast(i + 2);
        const d: i16 = @intCast(i + 3);

        try std.testing.expect(V2.init(a, b).eq(V2.init(a, b)));
        try std.testing.expect(V3.init(a, b, c).eq(V3.init(a, b, c)));
        try std.testing.expect(V4.init(a, b, c, d).eq(V4.init(a, b, c, d)));

        try std.testing.expect(!V2.init(a, b).eq(V2.init(a + 1, b)));
        try std.testing.expect(!V3.init(a, b, c).eq(V3.init(a + 1, b, c)));
        try std.testing.expect(!V4.init(a, b, c, d).eq(V4.init(a + 1, b, c, d)));

        try std.testing.expect(V2.init(a, b).ne(V2.init(a + 1, b)));
        try std.testing.expect(V3.init(a, b, c).ne(V3.init(a + 1, b, c)));
        try std.testing.expect(V4.init(a, b, c, d).ne(V4.init(a + 1, b, c, d)));

        try std.testing.expect(!V2.init(a, b).ne(V2.init(a, b)));
        try std.testing.expect(!V3.init(a, b, c).ne(V3.init(a, b, c)));
        try std.testing.expect(!V4.init(a, b, c, d).ne(V4.init(a, b, c, d)));
    }
}

test "dot_product" {
    const eq = std.testing.expectEqual;
    const F32 = fixed.F(16, 16);

    const V2 = V(2, F32);
    const V3 = V(3, F32);
    const V4 = V(4, F32);

    for (0..50) |i| {
        const a: i16 = @intCast(i + 0);
        const b: i16 = @intCast(i + 1);
        const c: i16 = @intCast(i + 2);
        const d: i16 = @intCast(i + 3);
        const e: i16 = @intCast(i + 4);
        const f: i16 = @intCast(i + 5);
        const g: i16 = @intCast(i + 6);
        const h: i16 = @intCast(i + 7);

        const v2_1 = V2.init(a, b);
        const v2_2 = V2.init(c, d);
        const v2_computed = v2_1.dot(v2_2);
        const v2_expected = F32.init(a * c + b * d, 1);
        try eq(v2_expected, v2_computed);

        const v3_1 = V3.init(a, b, c);
        const v3_2 = V3.init(d, e, f);
        const v3_computed = v3_1.dot(v3_2);
        const v3_expected = F32.init(a * d + b * e + c * f, 1);
        try eq(v3_expected, v3_computed);

        const v4_1 = V4.init(a, b, c, d);
        const v4_2 = V4.init(e, f, g, h);
        const v4_computed = v4_1.dot(v4_2);
        const v4_expected = F32.init(a * e + b * f + c * g + d * h, 1);
        try eq(v4_expected, v4_computed);
    }
}

test "unit_vectors" {
    const eq = std.testing.expectEqual;
    const F32 = fixed.F(16, 16);

    const V2 = V(2, F32);
    const V3 = V(3, F32);
    const V4 = V(4, F32);

    const one = F32.intToFixed(1);
    const zero = F32.intToFixed(0);

    const Vec2 = @Vector(2, F32.Fixed);
    const Vec3 = @Vector(3, F32.Fixed);
    const Vec4 = @Vector(4, F32.Fixed);

    try eq(Vec2{ one, zero }, V2.i().vector);
    try eq(Vec3{ one, zero, zero }, V3.i().vector);
    try eq(Vec4{ one, zero, zero, zero }, V4.i().vector);

    try eq(Vec2{ zero, one }, V2.j().vector);
    try eq(Vec3{ zero, one, zero }, V3.j().vector);
    try eq(Vec4{ zero, one, zero, zero }, V4.j().vector);

    try eq(Vec3{ zero, zero, one }, V3.k().vector);
    try eq(Vec4{ zero, zero, one, zero }, V4.k().vector);

    try eq(Vec4{ zero, zero, zero, one }, V4.l().vector);
}

test "linear_interpolation" {
    const eq = std.testing.expectEqual;
    const F32 = fixed.F(16, 16);
    const V2 = V(2, F32);

    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();

    for (0..100_000) |_| {
        const p1 = V2.init(rand.int(i8), rand.int(i8));
        const p2 = V2.init(rand.int(i8), rand.int(i8));

        try eq(p1, V2.lerp(p1, p2, 0));
        try eq(p2, V2.lerp(p1, p2, 1));
    }
}

test "to_integers" {
    const eq = std.testing.expectEqual;
    const F32 = fixed.F(16, 16);
    const V2 = V(2, F32);

    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();

    var expected: @Vector(2, i16) = undefined;

    for (0..100_000) |_| {
        const x = rand.int(i16);
        const y = rand.int(i16);

        expected[0] = x;
        expected[1] = y;
        const computed = V2.init(x, y).toInts();

        try eq(expected, computed);
    }
}

test "from_integers" {
    const eq = std.testing.expectEqual;
    const F32 = fixed.F(16, 16);
    const V2 = V(2, F32);

    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();

    var vector: @Vector(2, i16) = undefined;
    var array: [2]i16 = undefined;

    for (0..100_000) |_| {
        const x = rand.int(i16);
        const y = rand.int(i16);

        vector[0] = x;
        vector[1] = y;
        array[0] = x;
        array[1] = y;

        const expected = V2.init(x, y);
        const computed_vector = V2.fromInts(vector);
        const computed_array = V2.fromInts(array);

        try eq(expected, computed_vector);
        try eq(expected, computed_array);
    }
}

test "from_any" {
    const eq = std.testing.expectEqual;
    const F32 = fixed.F(16, 16);
    const V2 = V(2, F32);

    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();

    var vector: @Vector(2, i16) = undefined;
    var array: [2]i16 = undefined;
    var fix: F32 = undefined;
    var int: F32.Int = undefined;

    for (0..100_000) |_| {
        const x = rand.int(i16);
        const y = rand.int(i16);
        const q = rand.int(i16);

        fix = F32.fromInt(q);
        int = q;

        const expected_single = V2.init(q, q);
        const computed_fix = V2.fromAny(fix);
        const computed_int = V2.fromAny(int);
        try eq(expected_single, computed_fix);
        try eq(expected_single, computed_int);

        vector[0] = x;
        vector[1] = y;
        array[0] = x;
        array[1] = y;

        const expected_multiple = V2.init(x, y);
        const computed_vector = V2.fromAny(vector);
        const computed_array = V2.fromAny(array);
        try eq(expected_multiple, computed_vector);
        try eq(expected_multiple, computed_array);
    }
}

test "distance" {
    const eq = std.testing.expectEqual;
    const F32 = fixed.F(24, 8);
    const V2 = V(2, F32);

    try eq(F32.one, V2.i().dist(V2{}));
    try eq(F32.one, V2.j().dist(V2{}));
    try eq(F32.one.mul(2).sqrt(), V2.i().dist(V2.j()));

    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();

    for (0..100_000) |_| {
        const x1 = rand.int(i8);
        const y1 = rand.int(i8);
        const p1 = V2.init(if (x1 == 0) 1 else x1, if (y1 == 0) 1 else y1);

        const x2 = rand.int(i8);
        const y2 = rand.int(i8);
        const p2 = V2.init(if (x2 == 0) 1 else x2, if (y2 == 0) 1 else y2);

        const dx = p1.x().sub(p2.x());
        const dy = p1.y().sub(p2.y());

        const expected = dx.sqr().add(dy.sqr()).sqrt();
        const computed = p1.dist(p2);

        try eq(expected, computed);
    }
}

test "distance_squared" {
    const eq = std.testing.expectEqual;
    const F32 = fixed.F(24, 8);
    const V2 = V(2, F32);

    try eq(F32.one, V2.i().dist2(V2{}));
    try eq(F32.one, V2.j().dist2(V2{}));
    try eq(F32.one.mul(2), V2.i().dist2(V2.j()));

    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();

    for (0..100_000) |_| {
        const x1 = rand.int(i8);
        const y1 = rand.int(i8);
        const p1 = V2.init(if (x1 == 0) 1 else x1, if (y1 == 0) 1 else y1);

        const x2 = rand.int(i8);
        const y2 = rand.int(i8);
        const p2 = V2.init(if (x2 == 0) 1 else x2, if (y2 == 0) 1 else y2);

        const dx = p1.x().sub(p2.x());
        const dy = p1.y().sub(p2.y());

        const expected = dx.sqr().add(dy.sqr());
        const computed = p1.dist2(p2);

        try eq(expected, computed);
    }
}

test "integer_parts" {
    const eq = std.testing.expectEqual;
    const F32 = fixed.F(16, 16);
    const V2 = V(2, F32);

    const expected_1 = V2.init(1, -1);
    const computed_1 = V2.init(3, -3).div([2]i8{ 2, 2 }).integerParts();

    try eq(expected_1.x(), computed_1.x());
    try eq(expected_1.y(), computed_1.y());
}
