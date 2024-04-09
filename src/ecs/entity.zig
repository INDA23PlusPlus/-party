pub const Identifier = u32;
pub const Generation = u32;

pub const Entity = packed struct {
    const Self = @This();
    const Bits = @typeInfo(Self).Struct.backing_integer.?;

    identifier: Identifier = 0,
    generation: Generation = 0,

    pub inline fn toBits(self: Self) Bits {
        return @bitCast(self);
    }

    pub inline fn fromBits(bits: Bits) Self {
        return @bitCast(bits);
    }

    pub inline fn eq(a: Self, b: Self) bool {
        return a.toBits() == b.toBits();
    }

    pub inline fn ne(a: Self, b: Self) bool {
        return a.toBits() != b.toBits();
    }
};
