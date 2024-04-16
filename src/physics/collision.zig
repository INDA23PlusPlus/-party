const std = @import("std");
const ecs = @import("../ecs/ecs.zig");

// TODO:
//  - [X] Make collision system simd-based.
//  - [ ] Make CollisionQueue not suck.

// pub const max_collisions = ecs.world.N * (ecs.world.N - 1) / 2;

pub const CollisionQueue = struct {
    const Self = @This();
    const Key = struct { a: ecs.entity.Entity, b: ecs.entity.Entity };
    const Set = std.AutoArrayHashMap(Key, void);

    collisions: Set,

    pub fn pop(self: *Self) Key {
        return self.collisions.pop().key;
    }

    pub fn put(self: *Self, pair: Key) !void {
        try self.collisions.put(pair, {});
    }

    pub fn clear(self: *Self) void {
        self.collisions.clearRetainingCapacity();
    }

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .collisions = Set.init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.collisions.deinit();
    }
};

const CollisionMask = packed struct(u3) {
    /// There was a collision.
    xy: bool = false,

    /// The collision was caused by a movement in the x-axis.
    x: bool = false,

    /// The collision was caused by a movement in the y-axis.
    y: bool = false,
};

pub fn checkCollisions(
    ent1: ecs.entity.Entity,
    pos1: *ecs.component.Pos,
    col1: *ecs.component.Col,
    velocity: @Vector(2, i32),
    world: *ecs.world.World,
    collisions: *CollisionQueue,
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

        if (col1.layer.intersectsNot(col2.layer)) {
            continue;
        }

        const a = @intFromBool(pos1.pos + col1.dim + velocity > pos2.pos);
        const b = @intFromBool(pos2.pos + col2.dim > pos1.pos + velocity);
        const c = (a & b) != [_]u1{ 0, 0 };
        const d = @reduce(.And, c);

        if (d) {
            collided.xy = true;
            try collisions.put(.{ .a = ent1, .b = ent2 });

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

// ********************************************************************************************* //

const Pos = ecs.component.Pos;
const Col = ecs.component.Col;

pub const CollisionInfo = struct {
    first: ecs.entity.Entity = .{},
    other: ecs.entity.Entity = .{},
};

var col_table = [_]CollisionInfo{CollisionInfo{}} ** (ecs.world.N * ecs.world.N);

/// Performs collision checks for all entities that can collide.
/// Returns a slice containing pairs of entity identifiers, indicating a collision between them.
/// An empty array means no collision was detected.
pub fn checkCollisionsDeprecated(world: *ecs.world.World) []CollisionInfo {
    var cols: usize = 0;
    @memset(&col_table, .{ .first = .{}, .other = .{} });

    var q_a = world.query(&.{ Col, Pos }, &.{});
    while (q_a.next()) |current| {
        const c_a = q_a.get(Col) catch @panic("Failed to get Collider for current...\n");
        const p_a = q_a.get(Pos) catch @panic("Failed to get Position for current...\n");

        // TODO: This should not be N^2.
        var q_b = world.query(&.{ Col, Pos }, &.{});
        while (q_b.next()) |other| {
            // Dont test for self.
            if (other.eq(current)) {
                continue;
            }

            const c_b = q_b.get(Col) catch @panic("Failed to get Collider for other...\n");
            const p_b = q_b.get(Pos) catch @panic("Failed to get Position for other...\n");

            if (checkStaticClosedCollisionAABB(c_a, p_a, c_b, p_b)) {
                col_table[cols] = .{ .first = current, .other = other };
                cols += 1;
            }
        }
    }

    return col_table[0..cols];
}

/// Checks if entities overlap or are beside each other.
pub fn checkStaticClosedCollisionAABB(col_a: *Col, pos_a: *Pos, col_b: *Col, pos_b: *Pos) bool {
    const x = pos_a.pos[0] + col_a.dim[0] >= pos_b.pos[0] and pos_b.pos[0] + col_b.dim[0] >= pos_a.pos[0];
    const y = pos_a.pos[1] + col_a.dim[1] >= pos_b.pos[1] and pos_b.pos[1] + col_b.dim[1] >= pos_a.pos[1];
    return x and y;
}

/// Checks if a moving entity overlaps or is beside another entity.
pub fn checkDynamicClosedCollisionAABB(col_a: *Col, pos_a: *Pos, col_b: *Col, pos_b: *Pos, v_x: i32, v_y: i32) bool {
    const x = pos_a.pos[0] + v_x + col_a.dim[0] >= pos_b.pos[0] and pos_b.pos[0] + v_x + col_b.dim[0] >= pos_a.pos[0];
    const y = pos_a.pos[1] + v_y + col_a.dim[1] >= pos_b.pos[1] and pos_b.pos[1] + v_y + col_b.dim[1] >= pos_a.pos[1];
    return x and y;
}

/// Checks if entities overlap each other.
pub fn checkStaticOpenCollisionAABB(col_a: *Col, pos_a: *Pos, col_b: *Col, pos_b: *Pos) bool {
    const x = pos_a.pos[0] + col_a.dim[0] > pos_b.pos[0] and pos_b.pos[0] + col_b.dim[0] > pos_a.pos[0];
    const y = pos_a.pos[1] + col_a.dim[1] > pos_b.pos[1] and pos_b.pos[1] + col_b.dim[1] > pos_a.pos[1];
    return x and y;
}

/// Checks if a moving entity overlaps another entity.
pub fn checkDynamicOpenCollisionAABB(col_a: *Col, pos_a: *Pos, col_b: *Col, pos_b: *Pos, v_x: i32, v_y: i32) bool {
    const x = pos_a.pos[0] + v_x + col_a.dim[0] > pos_b.pos[0] and pos_b.pos[0] + v_x + col_b.dim[0] > pos_a.pos[0];
    const y = pos_a.pos[1] + v_y + col_a.dim[1] > pos_b.pos[1] and pos_b.pos[1] + v_y + col_b.dim[1] > pos_a.pos[1];
    return x and y;
}