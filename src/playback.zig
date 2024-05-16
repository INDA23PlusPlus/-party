const ecs = @import("ecs/ecs.zig");
const rl = @import("raylib");
const AudioManager = @import("AudioManager.zig");

pub fn update(world: *ecs.world.World, am: *AudioManager) void {
    var query = world.query(&.{ecs.component.Snd}, &.{});

    while (query.next()) |_| {
        const snd = query.get(ecs.component.Snd) catch unreachable;
        const audio = am.audio_map.get(snd.sound_hash) orelse continue;

        rl.playSound(audio);
    }
}
