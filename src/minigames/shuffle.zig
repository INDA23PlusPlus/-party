const std = @import("std");
const rl = @import("raylib");

const AssetManager = @import("../AssetManager.zig");
const Animation = @import("../animation/animations.zig").Animation;
const Invariables = @import("../Invariables.zig");
const game_list = @import("list.zig");
const simulation = @import("../simulation.zig");
const ecs = @import("../ecs/ecs.zig");
const animator = @import("../animation/animator.zig");
const input = @import("../input.zig");

const PlayerChange = enum { remove, add, nothing };

const colors: [8]rl.Color = .{
    rl.Color.red,
    rl.Color.green,
    rl.Color.blue,
    rl.Color.yellow,
    rl.Color.magenta,
    rl.Color.sky_blue,
    rl.Color.brown,
    rl.Color.white,
};

pub fn init(sim: *simulation.Simulation, _: input.Timeline) simulation.SimulationError!void {
    _ = try sim.world.spawnWith(.{
        ecs.component.Ctr{ .id = 0, .count = 180 }, // 3 second countdown
        ecs.component.Pos{ .pos = .{ 256, 144 } },
        ecs.component.Txt{ .string = "Shuffling...", .color = 0x000000FF, .font_size = 54 },
    });
}

pub fn update(sim: *simulation.Simulation, _: input.Timeline, _: Invariables) simulation.SimulationError!void {
    var counters = sim.world.query(&.{ecs.component.Ctr}, &.{});
    while (counters.next()) |_| {
        var ticks_left = counters.get(ecs.component.Ctr) catch unreachable;
        ticks_left.count = @max(0, @as(i32, @intCast(ticks_left.count)) - 1);

        if (ticks_left.count == 0) {
            sim.meta.minigame_id = @mod(sim.meta.minigame_prng.next(), game_list.list.len - 3) + 3;
        }
    }
}
