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
const crown = @import("../crown.zig");
const counter = @import("../counter.zig");

// Scoreboard:
// Deplete local score and add to global score
// Change minigame once all scores are depleted

// TODO:
// - Deplete the scores in order
// - Speed up the score animation as it goes on
// - Allow pressing button to skip score animation

pub fn init(sim: *simulation.Simulation, timeline: input.Timeline) !void {
    for (timeline.latest(), 0..) |inp, id| {
        if (inp.dpad == .Disconnected) continue;

        const global_score_counter = try counter.spawn(
            &sim.world,
            .{ constants.asset_resolution * 5, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(id)) },
            2,
            rl.Color.blue,
            sim.meta.global_score[id],
        );

        const local_score: u32 = switch (sim.meta.minigame_placements[id]) {
            0 => 20,
            1 => 10,
            2 => 5,
            else => 0,
        };

        const local_score_counter = try counter.spawn(
            &sim.world,
            .{ constants.asset_resolution * 8, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(id)) },
            2,
            rl.Color.green,
            local_score,
        );

        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = @intCast(id) },
            ecs.component.Ctr{ .count = local_score },
            ecs.component.Lnk{ .child = global_score_counter },
        });
        _ = try sim.world.spawnWith(.{
            ecs.component.Ctr{ .count = local_score },
            ecs.component.Lnk{ .child = local_score_counter },
        });

        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = @intCast(id) },
            ecs.component.Pos{ .pos = .{ constants.asset_resolution * 2, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(id)) } },
            ecs.component.Anm{ .animation = Animation.SmashIdle, .interval = 16, .looping = true },
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/smash_cat.png"),
                .w = 2,
                .h = 1,
                .tint = constants.player_colors[id],
            },
        });
    }

    try crown.init(sim, .{ 16, -10 });
}

pub fn update(sim: *simulation.Simulation, _: input.Timeline, _: Invariables) !void {
    if (try depleteSystem(sim)) {
        try transitionSystem(sim);
        // Sort here
    }

    try crown.update(sim);
    animator.update(&sim.world);
}

/// Returns true if the scores have been depleted.
fn depleteSystem(sim: *simulation.Simulation) !bool {
    var global_counter_query = sim.world.query(&.{
        ecs.component.Plr,
        ecs.component.Ctr,
        ecs.component.Lnk,
    }, &.{
        ecs.component.Str,
    });

    while (global_counter_query.next()) |_| {
        const plr = global_counter_query.get(ecs.component.Plr) catch unreachable;
        const ctr = global_counter_query.get(ecs.component.Ctr) catch unreachable;
        const lnk = global_counter_query.get(ecs.component.Lnk) catch unreachable;

        if (ctr.count > 0) {
            sim.meta.global_score[plr.id] += 1;
            ctr.count -= 1;
            _ = try counter.increment(&sim.world, lnk.child.?);
        }
    }

    var local_counter_query = sim.world.query(&.{
        ecs.component.Ctr,
        ecs.component.Lnk,
    }, &.{
        ecs.component.Plr,
        ecs.component.Str,
    });

    var depleted = true;

    while (local_counter_query.next()) |_| {
        const ctr = local_counter_query.get(ecs.component.Ctr) catch unreachable;
        const lnk = local_counter_query.get(ecs.component.Lnk) catch unreachable;

        if (ctr.count > 0) {
            ctr.count -= 1;
            depleted = ctr.count == 0;
            _ = try counter.decrement(&sim.world, lnk.child.?);
        }
    }

    return depleted;
}

/// Waits then transitions to gamewheel or winscreen.
fn transitionSystem(sim: *simulation.Simulation) !void {
    sim.meta.minigame_timer += 1;

    if (sim.meta.minigame_timer < 2 * constants.ticks_per_second) return;

    for (sim.meta.global_score) |score| {
        if (score >= 50) {
            sim.meta.minigame_id = constants.minigame_winscreen;
            return;
        }
    }

    sim.meta.minigame_id = constants.minigame_gamewheel;
}

// ************************************************** //

/// Instantly skips score animation if the player presses a button
fn skipSystem(sim: *simulation.Simulation, inputs: input.Timeline) !void {
    const latest = inputs.latest();
    var query = sim.world.query(&.{ ecs.component.Plr, ecs.component.Lnk }, &.{});
    while (query.next()) |_| {
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const lnk = query.get(ecs.component.Lnk) catch unreachable;
        const score_counter = lnk.child.?; // should not be null

        const state = latest[plr.id];

        if (state.button_a == .Pressed or state.button_b == .Pressed) {
            const ctr = try sim.world.inspect(score_counter, ecs.component.Ctr);
            sim.meta.global_score[plr.id] += ctr.count;
            while (try counter.decrement(&sim.world, score_counter)) {}
        }
    }
}

fn updatePos(sim: *simulation.Simulation) !void {
    const scores = sim.meta.global_score;
    var scores_with_id: [8][2]u32 = .{.{ undefined, undefined }} ** constants.max_player_count;
    for (scores, 0..scores.len) |score, id| {
        scores_with_id[id] = .{ score, @as(u32, @intCast(id)) };
    }
    std.mem.sort([2]u32, &scores_with_id, {}, lessThanFn);
    var query = sim.world.query(&.{ ecs.component.Plr, ecs.component.Pos, ecs.component.Lnk }, &.{});
    while (query.next()) |_| {
        //TODO Make the players switch postion
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const pos = query.get(ecs.component.Pos) catch unreachable;
        const lnk = query.get(ecs.component.Lnk) catch unreachable;

        for (scores_with_id, 0..8) |score_with_id, placement| {
            if (plr.id == score_with_id[1]) {
                const ctr_pos = sim.world.inspect(lnk.child.?, ecs.component.Pos) catch unreachable;
                pos.pos = .{ constants.asset_resolution * 4, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(placement)) };
                ctr_pos.pos = .{ constants.asset_resolution * 4, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(placement)) };
            }
        }
    }
}

fn lessThanFn(_: void, a: [2]u32, b: [2]u32) bool {
    return a[0] > b[0];
}
