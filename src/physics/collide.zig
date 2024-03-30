const std = @import("std");
const ecs = @import("../ecs/ecs.zig");

pub const CollisionInfo = struct {
    first: u32,
    other: u32,
    fn init() CollisionInfo {
        return .{ .first = 0, .other = 0 };
    }
};

var col_table = [_]CollisionInfo{CollisionInfo.init()} ** 65536;

/// Performs collision checks for all entites that can collide.
/// Returns a slice containing pairs of entity identifiers, indicating a collision between them.
/// An empty array means no collision was detected.
pub fn check_collisions(world: *ecs.World) []CollisionInfo {
    var cols: usize = 0;
    @memset(&col_table, .{ .first = 0, .other = 0 });

    var q_a = world.query(&.{ ecs.Collider, ecs.Position }, &.{});
    while (q_a.next()) |current| {
        const c_a = q_a.get(ecs.Collider) catch @panic("Failed to get Collider for current...\n");
        const p_a = q_a.get(ecs.Position) catch @panic("Failed to get Position for current...\n");

        // TODO: This should not be N^2.
        var q_b = world.query(&.{ ecs.Collider, ecs.Position }, &.{});
        while (q_b.next()) |other| {
            if (other.identifier == current.identifier) { // Dont test for self.
                continue;
            }
            const c_b = q_b.get(ecs.Collider) catch @panic("Failed to get Collider for other...\n");
            const p_b = q_b.get(ecs.Position) catch @panic("Failed to get Position for other...\n");

            if (aabb_collision(c_a, p_a, c_b, p_b)) {
                col_table[cols] = .{ .first = current.identifier, .other = other.identifier };
                cols += 1;
            }
        }
    }

    return col_table[0..cols];
}

fn aabb_collision(col_a: *ecs.Collider, pos_a: *ecs.Position, col_b: *ecs.Collider, pos_b: *ecs.Position) bool {
    const x = pos_a.x + col_a.w >= pos_b.x and pos_b.x + col_b.w >= pos_a.x;
    const y = pos_a.y + col_a.h >= pos_b.y and pos_b.y + col_b.h >= pos_a.y;
    return x and y;
}
