const std = @import("std");
const ecs = @import("../ecs/ecs.zig");

// TODO:
//  - [X] Make collision system simd-based.
//  - [ ] Make CollisionQueue not suck.

// pub const max_collisions = (ecs.world.N * (ecs.world.N - 1)) / 2;

/// Bitmask for collisions, used for filtering and resolving collisions between entities.
pub const Layer = packed struct {
    const Self = @This();
    const Bits = @typeInfo(Self).Struct.backing_integer.?;

    base: bool = true,
    player: bool = false,
    damaging: bool = false,
    killing: bool = false,
    pushing: bool = false,
    bouncing: bool = false,
    // Add more layers here and set their default to false.

    pub inline fn complement(self: Self) Self {
        const bits: Bits = @bitCast(self);

        return @bitCast(~bits);
    }

    pub inline fn intersects(self: Self, other: Self) bool {
        const a: Bits = @bitCast(self);
        const b: Bits = @bitCast(other);

        return a & b != 0;
    }

    pub inline fn coincides(self: Self, other: Self) bool {
        const a: Bits = @bitCast(self);
        const b: Bits = @bitCast(other);

        return a == b;
    }
};

pub const Collision = packed struct {
    bidirectional: bool = false,
};

pub const CollisionQueue = struct {
    const Self = @This();
    pub const Key = packed struct { a: ecs.entity.Entity, b: ecs.entity.Entity };
    const Map = std.AutoArrayHashMapUnmanaged(Key, void);

    collisions: Map,

    pub fn init(arena: std.mem.Allocator) !Self {
        const collisions = try Map.init(arena, &.{}, &.{});

        return Self{
            .collisions = collisions,
        };
    }

    pub fn put(self: *Self, arena: std.mem.Allocator, pair: Key) !void {
        try self.collisions.put(arena, pair, {});
    }
};

/// Note, if .xy is false, then neither .x nor .y can be true.
/// Valid: 000, 100, 110, 101, 111.
/// Invalid: 010, 001, 011.
const CollisionMask = packed struct(u3) {
    /// There was a collision.
    xy: bool = false,

    /// The collision was caused by a movement in the x-axis.
    x: bool = false,

    /// The collision was caused by a movement in the y-axis.
    y: bool = false,
};

/// Adds collisions to the collision queue. They are guaranteed to not be the same entity.
pub fn checkCollisions(
    ent1: ecs.entity.Entity,
    pos1: *ecs.component.Pos,
    col1: *ecs.component.Col,
    velocity: @Vector(2, i32),
    world: *ecs.world.World,
    collisions: *CollisionQueue,
    allocator: std.mem.Allocator,
) !CollisionMask {
    var query = world.query(&.{
        ecs.component.Pos,
        ecs.component.Col,
    }, &.{});

    var collided = CollisionMask{};

    while (query.next()) |ent2| {
        if (ent1.eq(ent2)) {
            continue;
        }

        const pos2 = query.get(ecs.component.Pos) catch unreachable;
        const col2 = query.get(ecs.component.Col) catch unreachable;

        if (!(col1.layer.intersects(col2.mask) or col1.mask.intersects(col2.layer))) {
            continue;
        }

        const a = @intFromBool(pos1.pos + col1.dim + velocity > pos2.pos);
        const b = @intFromBool(pos2.pos + col2.dim > pos1.pos + velocity);
        const c = (a & b) != [_]u1{ 0, 0 };
        const d = @reduce(.And, c);

        if (d) {
            collided.xy = true;
            try collisions.put(allocator, .{
                .a = @bitCast(@min(ent1.toBits(), ent2.toBits())),
                .b = @bitCast(@max(ent1.toBits(), ent2.toBits())),
            });

            const x_velocity = velocity & [_]i32{ ~@as(i32, 0), 0 };
            const x_a = @intFromBool(pos1.pos + col1.dim + x_velocity > pos2.pos);
            const x_b = @intFromBool(pos2.pos + col2.dim > pos1.pos + x_velocity);
            const x_c = (x_a & x_b) != [_]u1{ 0, 0 };
            const x_d = @reduce(.And, x_c);

            if (x_d) collided.x = true;

            const y_velocity = velocity & [_]i32{ 0, ~@as(i32, 0) };
            const y_a = @intFromBool(pos1.pos + col1.dim + y_velocity > pos2.pos);
            const y_b = @intFromBool(pos2.pos + col2.dim > pos1.pos + y_velocity);
            const y_c = (y_a & y_b) != [_]u1{ 0, 0 };
            const y_d = @reduce(.And, y_c);

            if (y_d) collided.y = true;
        }
    }

    return collided;
}

pub inline fn intersects(
    pos1: *ecs.component.Pos,
    col1: *ecs.component.Col,
    pos2: *ecs.component.Pos,
    col2: *ecs.component.Col,
) bool {
    const a = @intFromBool(pos1.pos + col1.dim > pos2.pos);
    const b = @intFromBool(pos2.pos + col2.dim > pos1.pos);
    const c = (a & b) != [_]u1{ 0, 0 };

    return @reduce(.And, c);
}

pub inline fn intersectsAt(
    pos1: *ecs.component.Pos,
    col1: *ecs.component.Col,
    pos2: *ecs.component.Pos,
    col2: *ecs.component.Col,
    offset: @Vector(2, i32),
) bool {
    const a = @intFromBool(pos1.pos + col1.dim + offset > pos2.pos);
    const b = @intFromBool(pos2.pos + col2.dim > pos1.pos + offset);
    const c = (a & b) != [_]u1{ 0, 0 };

    return @reduce(.And, c);
}
