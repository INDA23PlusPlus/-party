const std = @import("std");
const fixed = @import("fixed.zig");

pub const P = V;

pub fn V(comptime integer_bits: u16, comptime fractional_bits: u16) type {
    return struct {
        const Self = @This();
        const Fixed = fixed.F(integer_bits, fractional_bits);

        x: Fixed,
        y: Fixed,
        comptime F: type = Fixed,

        pub inline fn init(x: anytype, y: anytype) Self {
            const X = @TypeOf(x);
            const Y = @TypeOf(y);
            const x_info = @typeInfo(X);
            const y_info = @typeInfo(Y);

            const xx = if (x_info == .Int or x_info == .ComptimeInt) blk: {
                break :blk Fixed.init(x, 1);
            } else if (X == Fixed) blk: {
                break :blk x;
            } else {
                @compileError("Expected type " ++ @typeName(Fixed.Int) ++ ", but got type " ++ @typeName(X));
            };

            const yy = if (y_info == .Int or y_info == .ComptimeInt) blk: {
                break :blk Fixed.init(y, 1);
            } else if (Y == fixed) blk: {
                break :blk y;
            } else {
                @compileError("Expected type " ++ @typeName(Fixed.Int) ++ ", but got type " ++ @typeName(Y));
            };

            return Self{ .x = xx, .y = yy };
        }
    };
}
