const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const render = @import("../render.zig");
const input = @import("../input.zig");
const AssetManager = @import("../AssetManager.zig");
const Invariables = @import("../Invariables.zig");
const Animation = @import("../animation/animations.zig").Animation;
const animator = @import("../animation/animator.zig");
const movement = @import("../physics/movement.zig");
const collision = @import("../physics/collision.zig");
const constants = @import("../constants.zig");

pub fn init(sim: *simulation.Simulation, _: input.Timeline) !void {
    for (0..8) |id| {
        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = @intCast(id) },
            ecs.component.Pos{ .pos = .{ constants.asset_resolution * 4, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(id)) } },
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/kattis.png"),
                .tint = constants.player_colors[id],
            },
            ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
        });
    }

    _ = try sim.world.spawnWith(.{
        ecs.component.Ctr{ .id = 100, .count = 30 * 60 },
    });
    _ = try sim.world.spawnWith(.{
        ecs.component.Ctr{ .id = 101, .count = 10 * 60 },
    });
}
pub fn update(sim: *simulation.Simulation, inputs: input.Timeline, invar: Invariables) !void {
    _ = inputs;
    var collisions = collision.CollisionQueue.init(invar.arena) catch @panic("could not initialize collision queue");

    movement.update(&sim.world, &collisions, invar.arena) catch @panic("movement system failed");

    animator.update(&sim.world);
    var query = sim.world.query(&.{ecs.component.Ctr}, &.{ ecs.component.Plr, ecs.component.Tex });
    while (query.next()) |entity| {
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        switch (ctr.id) {
            100 => {
                if (ctr.count == 0) {
                    for (sim.meta.global_score, 0..constants.max_player_count) |score, id| {
                        std.debug.print("Score {d}: {d}\n", .{ id, score });
                    }
                    sim.meta.minigame_id = 4;
                    return;
                } else {
                    ctr.count -= 1;
                }
            },
            101 => {
                if (ctr.count == 0) {
                    for (sim.meta.global_score, 0..constants.max_player_count) |score, id| {
                        std.debug.print("Score {d}: {d}\n", .{ id, score });
                    }
                    try updateScore(sim);
                    sim.world.kill(entity);
                    return;
                } else {
                    ctr.count -= 1;
                }
            },
            else => {},
        }
    }
}

fn updateScore(sim: *simulation.Simulation) !void {
    for (0..constants.max_player_count) |id| {
        const mingame_placement = sim.meta.minigame_placements[id];
        switch (mingame_placement) {
            1 => {
                sim.meta.global_score[id] += 10;
                sim.meta.minigame_placements[id] = undefined;
            },
            2 => {
                sim.meta.global_score[id] += 5;
                sim.meta.minigame_placements[id] = undefined;
            },
            3 => {
                sim.meta.global_score[id] += 2;
                sim.meta.minigame_placements[id] = undefined;
            },

            0 => {
                std.debug.print("Hpppsan det var fel\n", .{});
                sim.meta.minigame_placements[id] = undefined;
            },

            else => {
                sim.meta.minigame_placements[id] = undefined;
            },
        }
    }
}
