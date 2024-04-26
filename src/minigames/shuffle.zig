const std = @import("std");
const rl = @import("raylib");

const AssetManager = @import("../AssetManager.zig");
const Animation = @import("../animation/animations.zig").Animation;
const Invariables = @import("../Invariables.zig");
const game_list = @import("list.zig");
const simulation = @import("../simulation.zig");
const input = @import("../input.zig");
const ecs = @import("../ecs/ecs.zig");
const animator = @import("../animation/animator.zig");

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

pub fn init(sim: *simulation.Simulation, _: []const input.InputState) simulation.SimulationError!void {
    _ = try sim.world.spawnWith(.{
        ecs.component.Ctr{ .id = 0, .counter = 180 }, // 3 second countdown
        ecs.component.Pos{ .pos = .{ 256, 144 } },
        ecs.component.Txt{ .string = "Shuffling...", .color = 0x000000FF, .font_size = 54 },
    });
}

pub fn update(sim: *simulation.Simulation, inputs_timeline: []const input.InputState, _: Invariables) simulation.SimulationError!void {
    const inputs = inputs_timeline[inputs_timeline.len - 1];
    var players = sim.world.query(&.{ecs.component.Plr}, &.{});
    var player_changes = [_]PlayerChange{.nothing} ** inputs.len;
    var player_ids: [inputs.len]?ecs.entity.Entity = [_]?ecs.entity.Entity{null} ** inputs.len;
    var player_count: u8 = 0;

    while (players.next()) |entity| {
        const plr = players.get(ecs.component.Plr) catch unreachable;
        player_ids[plr.id] = entity;
        player_count += 1;
    }

    for (inputs, 0..) |ins, index| {
        if (ins.is_connected and player_ids[index] == null) {
            player_changes[index] = .add;
            player_count += 1;
        }

        if (!ins.is_connected and player_ids[index] != null) {
            player_changes[index] = .remove;
        }
    }

    for (player_changes, player_ids, 0..) |change, entity, index| {
        if (change == .add) {
            player_ids[index] = try sim.world.spawnWith(.{
                ecs.component.Plr{ .id = @truncate(index) },
                ecs.component.Pos{ .pos = .{ 16, 16 + 24 * @as(i32, @intCast(index)) } },
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/kattis.png"),
                    .tint = colors[index],
                },
                ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
            });
        } else if (change == .remove) {
            if (entity) |e| {
                sim.world.kill(e);
            }
        }
    }

    animator.update(&sim.world);

    var counters = sim.world.query(&.{ecs.component.Ctr}, &.{});
    while (counters.next()) |_| {
        var ticks_left = counters.get(ecs.component.Ctr) catch unreachable;
        ticks_left.counter -= 1;

        if (ticks_left.counter == 0) {
            var rng = std.rand.DefaultPrng.init(sim.meta.seed);
            sim.meta.minigame_id = @mod(rng.next(), game_list.list.len - 3) + 3;
        }
    }
}
