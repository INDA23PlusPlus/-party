const std = @import("std");
const fixed = @import("fixed.zig");

// TODO
//  - [ ] mul() overflow check
//  - [ ] div() overflow check
//  - [ ] lerp() test
//  - [ ] proj()
//  - [ ] dist()
//  - [ ] swizzle()
//  - [ ] infer()
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

        vector: Vector,
        comptime Fixed: type = F,

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
                    const X = @TypeOf(x_init);
                    const Y = @TypeOf(y_init);

                    const x_info = @typeInfo(X);
                    const y_info = @typeInfo(Y);

                    const xx = if (x_info == .Int or x_info == .ComptimeInt) blk: {
                        break :blk F.init(x_init, 1).bits;
                    } else if (X == Fixed) blk: {
                        break :blk x_init.bits;
                    } else {
                        @compileError("Expected type " ++ @typeName(Fixed.Int) ++ ", but got type " ++ @typeName(X));
                    };

                    const yy = if (y_info == .Int or y_info == .ComptimeInt) blk: {
                        break :blk F.init(y_init, 1).bits;
                    } else if (Y == Fixed) blk: {
                        break :blk y_init.bits;
                    } else {
                        @compileError("Expected type " ++ @typeName(Fixed.Int) ++ ", but got type " ++ @typeName(Y));
                    };

                    return Self{ .vector = .{ xx, yy } };
                }

                pub inline fn cross(self: Self, vec: Self) F {
                    return self.x().mul(vec.y()).sub(self.y().mul(vec.x()));
                }
            },
            inline 3 => struct {
                pub inline fn init(x_init: anytype, y_init: anytype, z_init: anytype) Self {
                    const X = @TypeOf(x_init);
                    const Y = @TypeOf(y_init);
                    const Z = @TypeOf(z_init);

                    const x_info = @typeInfo(X);
                    const y_info = @typeInfo(Y);
                    const z_info = @typeInfo(Z);

                    const xx = if (x_info == .Int or x_info == .ComptimeInt) blk: {
                        break :blk F.init(x_init, 1).bits;
                    } else if (X == Fixed) blk: {
                        break :blk x_init.bits;
                    } else {
                        @compileError("Expected type " ++ @typeName(Fixed.Int) ++ ", but got type " ++ @typeName(X));
                    };

                    const yy = if (y_info == .Int or y_info == .ComptimeInt) blk: {
                        break :blk F.init(y_init, 1).bits;
                    } else if (Y == Fixed) blk: {
                        break :blk y_init.bits;
                    } else {
                        @compileError("Expected type " ++ @typeName(Fixed.Int) ++ ", but got type " ++ @typeName(Y));
                    };

                    const zz = if (z_info == .Int or z_info == .ComptimeInt) blk: {
                        break :blk F.init(z_init, 1).bits;
                    } else if (Z == Fixed) blk: {
                        break :blk z_init.bits;
                    } else {
                        @compileError("Expected type " ++ @typeName(Fixed.Int) ++ ", but got type " ++ @typeName(Z));
                    };

                    return Self{ .vector = .{ xx, yy, zz } };
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
                    const X = @TypeOf(x_init);
                    const Y = @TypeOf(y_init);
                    const Z = @TypeOf(z_init);
                    const W = @TypeOf(w_init);

                    const x_info = @typeInfo(X);
                    const y_info = @typeInfo(Y);
                    const z_info = @typeInfo(Z);
                    const w_info = @typeInfo(W);

                    const xx = if (x_info == .Int or x_info == .ComptimeInt) blk: {
                        break :blk F.init(x_init, 1).bits;
                    } else if (X == Fixed) blk: {
                        break :blk x_init.bits;
                    } else {
                        @compileError("Expected type " ++ @typeName(Fixed.Int) ++ ", but got type " ++ @typeName(X));
                    };

                    const yy = if (y_info == .Int or y_info == .ComptimeInt) blk: {
                        break :blk F.init(y_init, 1).bits;
                    } else if (Y == Fixed) blk: {
                        break :blk y_init.bits;
                    } else {
                        @compileError("Expected type " ++ @typeName(Fixed.Int) ++ ", but got type " ++ @typeName(Y));
                    };

                    const zz = if (z_info == .Int or z_info == .ComptimeInt) blk: {
                        break :blk F.init(z_init, 1).bits;
                    } else if (Z == Fixed) blk: {
                        break :blk z_init.bits;
                    } else {
                        @compileError("Expected type " ++ @typeName(Fixed.Int) ++ ", but got type " ++ @typeName(Z));
                    };

                    const ww = if (w_info == .Int or w_info == .ComptimeInt) blk: {
                        break :blk F.init(w_init, 1).bits;
                    } else if (W == Fixed) blk: {
                        break :blk w_init.bits;
                    } else {
                        @compileError("Expected type " ++ @typeName(Fixed.Int) ++ ", but got type " ++ @typeName(W));
                    };

                    return Self{ .vector = .{ xx, yy, zz, ww } };
                }
            },
            inline else => unreachable,
        };

        pub inline fn add(augend: Self, addend: anytype) Self {
            const Type = @TypeOf(addend);
            const info = @typeInfo(Type);

            if (Type == Self) {
                return Self{ .vector = augend.vector + addend.vector };
            }

            if (Type == F) {
                return Self{ .vector = augend.vector + @as(Vector, @splat(addend.bits)) };
            }

            if (info == .Int or info == .ComptimeInt) {
                return Self{ .vector = augend.vector + @as(Vector, @splat(F.intToFixed(addend))) };
            }

            @compileError("Expected type " ++ @typeName(Self) ++ " or " ++ @typeName(F) ++ ", but got type " ++ @typeName(Type));
        }

        pub inline fn sub(minuend: Self, subtrahend: anytype) Self {
            const Type = @TypeOf(subtrahend);
            const info = @typeInfo(Type);

            if (Type == Self) {
                return Self{ .vector = minuend.vector - subtrahend.vector };
            }

            if (Type == F) {
                return Self{ .vector = minuend.vector - @as(Vector, @splat(subtrahend.bits)) };
            }

            if (info == .Int or info == .ComptimeInt) {
                return Self{ .vector = minuend.vector - @as(Vector, @splat(F.intToFixed(subtrahend))) };
            }

            @compileError("Expected type " ++ @typeName(Self) ++ " or " ++ @typeName(F) ++ ", but got type " ++ @typeName(Type));
        }

        pub inline fn mul(multiplicand: Self, multiplier: anytype) Self {
            const Type = @TypeOf(multiplier);
            const info = @typeInfo(Type);

            // Hadamard product.
            if (Type == Self) {
                return Self{ .vector = @as(Vector, @truncate((@as(LargeVector, multiplicand.vector) * @as(LargeVector, multiplier.vector)) >> @splat(F.shift))) };
            }

            if (Type == F) {
                return Self{ .vector = @as(Vector, @truncate((@as(LargeVector, multiplicand.vector) * @as(LargeVector, @splat(multiplier.bits))) >> @splat(F.shift))) };
            }

            if (info == .Int or info == .ComptimeInt) {
                return Self{ .vector = @as(Vector, @truncate((@as(LargeVector, multiplicand.vector) * @as(LargeVector, @splat(F.intToFixed(multiplier)))) >> @splat(F.shift))) };
            }

            @compileError("Expected type " ++ @typeName(Self) ++ " or " ++ @typeName(F) ++ ", but got type " ++ @typeName(Type));
        }

        pub inline fn div(dividend: Self, divisor: anytype) Self {
            const Type = @TypeOf(divisor);
            const info = @typeInfo(Type);

            if (Type == Self) {
                return Self{ .vector = @as(Vector, @truncate(@divFloor(@as(LargeVector, dividend.vector) << @splat(F.shift), @as(LargeVector, divisor.vector)))) };
            }

            if (Type == F) {
                return Self{ .vector = @as(Vector, @truncate(@divFloor(@as(LargeVector, dividend.vector) << @splat(F.shift), @as(LargeVector, @splat(divisor.bits))))) };
            }

            if (info == .Int or info == .ComptimeInt) {
                return Self{ .vector = @as(Vector, @truncate(@divFloor(@as(LargeVector, dividend.vector) << @splat(F.shift), @as(LargeVector, @splat(F.intToFixed(divisor)))))) };
            }

            @compileError("Expected type " ++ @typeName(Self) ++ " or " ++ @typeName(F) ++ ", but got type " ++ @typeName(Type));
        }

        pub inline fn reduce(self: Self, comptime op: std.builtin.ReduceOp) F {
            switch (op) {
                .Add => return fixedCast(@reduce(.Add, self.vector)),
                .Max => return fixedCast(@reduce(.Max, self.vector)),
                .Min => return fixedCast(@reduce(.Min, self.vector)),
                else => @compileError("Operation not supported"),
            }
        }

        pub inline fn eq(a: Self, b: Self) bool {
            return @reduce(std.builtin.ReduceOp.And, a.vector == b.vector);
        }

        pub inline fn ne(a: Self, b: Self) bool {
            return @reduce(std.builtin.ReduceOp.Or, a.vector != b.vector);
        }

        pub inline fn mag2(self: Self) F {
            return self.mul(self).reduce(.Add);
        }

        pub inline fn mag(self: Self) F {
            return self.mag2().sqrt();
        }

        pub inline fn dot(self: Self, vec: Self) F {
            return self.mul(vec).reduce(.Add);
        }

        pub inline fn neg(self: Self) Self {
            return self.mul(-1);
        }

        pub inline fn lerp(from: Self, to: Self, t: anytype) Self {
            const Type = @TypeOf(t);
            const info = @typeInfo(Type);

            if (Type == F) {
                return from.add(to.sub(from)).mul(@as(Vector, @splat(t.bits)));
            }

            if (info == .Int or info == .ComptimeInt) {
                return from.add(to.sub(from)).mul(@as(Vector, @splat(F.fixedFromInt(t))));
            }

            @compileError("Expected type " ++ @typeName(F) ++ ", but got type " ++ @typeName(Type));
        }

        pub inline fn dist(from: Self, to: Self) Self {
            _ = from;
            _ = to;
        }

        inline fn infer(value: anytype) Vector {
            const Type = @TypeOf(value);
            // const info = @typeInfo(Type);

            if (Type == Self) {
                return value.vector;
            }

            // switch (info) {
            //     .Array => |array| {
            //         if (array.child == F) {
            //             return value;
            //         }

            //         switch (@typeInfo(array.child)) {
            //             inline .Int => return fixedFromInt(value),
            //             inline .ComptimeInt => return fixedFromInt(value),
            //             inline else => @compileError("Expected type " ++ @typeName(Self) ++ " or " ++ @typeName(Fixed) ++ ", but got type " ++ @typeName(Type)),
            //         }
            //     },
            //     .Vector => |vector| {},
            // }

            return @splat(F.infer(value));
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
        const y = @divFloor(j, 3);
        const z = j;
        const w = @divFloor(j, 2) + 1;
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

test "projection" {}

test "negation" {}

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
