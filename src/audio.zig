const ecs = @import("ecs/ecs.zig");

/// Updates the audio engine. Must be called before all sounds are created in a frame.
pub fn update(world: *ecs.world.World) void {
    var query = world.query(&.{ecs.component.Snd}, &.{});

    while (query.next()) |entity| {
        world.demote(entity, &.{ecs.component.Snd});
    }
}
