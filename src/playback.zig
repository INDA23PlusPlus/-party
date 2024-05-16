const ecs = @import("ecs/ecs.zig");
const rl = @import("raylib");
const AudioManager = @import("AudioManager.zig");

pub fn update(world: *ecs.world.World, am: *AudioManager) void {
    var query = world.query(&.{ ecs.component.Snd }, &.{});

    while (query.next()) |_| {
        rl.playSound(am.path_to_key(am.))
    }

}