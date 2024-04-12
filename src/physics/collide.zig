const std = @import("std");
const ecs = @import("../ecs/ecs.zig");

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
pub fn checkCollisions(world: *ecs.world.World) []CollisionInfo {
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

/// Moves entities with Pos, Mov, and Col components.
/// If a collision occurs, it is added to the collision queue.
pub fn movementSystem(world: *ecs.world.World, collisions: *CollisionQueue) !void {
    var query = world.query(&.{
        ecs.component.Pos,
        ecs.component.Col,
        ecs.component.Mov,
    }, &.{});

    while (query.next()) |entity| {
        const pos = query.get(ecs.component.Pos) catch unreachable;
        const col = query.get(ecs.component.Col) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;

        mov.subpixel = mov.subpixel.add(mov.velocity);
        const movee: @Vector(2, i16) = mov.subpixel.integerParts().toInts();

        if (@reduce(.And, movee == @Vector(2, i32){ 0, 0 })) {
            continue;
        }

        mov.subpixel = mov.subpixel.sub(movee);

        var move: @Vector(2, i32) = movee;

        // Move in the x-axis and the y-axis.
        while (@reduce(.And, move != @Vector(2, i32){ 0, 0 })) {
            const u: @Vector(2, i32) = @intFromBool(move > @Vector(2, i32){ 0, 0 });
            const v: @Vector(2, i32) = @intFromBool(move < @Vector(2, i32){ 0, 0 });
            const velocity = u - v;

            std.debug.print("xy: {} {}\n", .{ velocity[0], velocity[1] });

            if (try collisionSystem(
                entity,
                pos,
                col,
                velocity,
                world,
                collisions,
            )) {
                break;
            } else {
                pos.pos += velocity;
                move -= velocity;
            }
        }

        // Move in the x-axis.
        if (move[0] != 0) {
            const velocity: @Vector(2, i32) = .{ (@as(i32, @intFromBool(move[0] > 0)) << 1) - 1, 0 };
            std.debug.print("x: {} {}\n", .{ velocity[0], velocity[1] });
            while (move[0] != 0) {
                if (try collisionSystem(
                    entity,
                    pos,
                    col,
                    velocity,
                    world,
                    collisions,
                )) {
                    move[0] = 0;
                    break;
                } else {
                    pos.pos += velocity;
                    move -= velocity;
                }
            }
        }

        // Move in the y-axis.
        if (move[1] != 0) {
            const velocity: @Vector(2, i32) = .{ 0, (@as(i32, @intFromBool(move[1] > 0)) << 1) - 1 };
            std.debug.print("y: {} {}\n", .{ velocity[0], velocity[1] });
            while (move[1] != 0) {
                if (try collisionSystem(
                    entity,
                    pos,
                    col,
                    velocity,
                    world,
                    collisions,
                )) {
                    move[1] = 0;
                    break;
                } else {
                    pos.pos += velocity;
                    move -= velocity;
                }
            }
        }
    }
}

pub const max_collisions = ecs.world.N * (ecs.world.N - 1) / 2;

pub const CollisionQueue = struct {
    const Self = @This();
    const Key = struct { ecs.entity.Entity, ecs.entity.Entity };
    const Set = std.AutoArrayHashMap(Key, void);

    collisions: Set,

    pub fn pop(self: *Self) Key {
        return self.collisions.pop().key;
    }

    pub fn put(self: *Self, pair: Key) !void {
        try self.collisions.put(pair, {});
    }

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .collisions = Set.init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.collisions.deinit();
    }
};

fn collisionSystem(
    ent1: ecs.entity.Entity,
    pos1: *ecs.component.Pos,
    col1: *ecs.component.Col,
    velocity: @Vector(2, i32),
    world: *ecs.world.World,
    collisions: *CollisionQueue,
) !bool {
    var query = world.query(&.{
        ecs.component.Pos,
        ecs.component.Col,
    }, &.{});

    var collided = false;

    while (query.next()) |ent2| {
        if (ent1.eq(ent2)) {
            continue;
        }

        const pos2 = query.get(ecs.component.Pos) catch unreachable;
        const col2 = query.get(ecs.component.Col) catch unreachable;

        const a = @reduce(.And, pos1.pos + col1.dim + velocity > pos2.pos);
        const b = @reduce(.And, pos2.pos + col2.dim > pos1.pos + velocity);

        if (a and b) {
            try collisions.put(.{ ent1, ent2 });
            collided = true;
        }
    }

    return collided;
}
