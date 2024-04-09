const ecs = @import("ecs/ecs.zig");

/// Simulate one tick in the game world.
/// All generic game code will be called from this function and should not
/// use anything outside of the world or the input frame. Failing to do so
/// will lead to inconsistencies.
pub fn simulate(world: *ecs.world.World) !void {
    // TODO: Add input as an argument.

    var pos_query = world.query(&.{ecs.component.Pos}, &.{});
    while (pos_query.next()) |_| {
        const pos = try pos_query.get(ecs.component.Pos);
        pos.x += 1;
        pos.y += 1;
    }
}
