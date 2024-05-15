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

const score_distribution: [constants.max_player_count]u32 = .{ 400, 20, 10, 0, 0, 0, 0, 0 }; // completely arbitrary score values, open to change
const wait_time_ticks = 3 * constants.ticks_per_second; // time before switching minigame

fn scoreFromPlacement(placement: u32) u32 {
    if (placement >= score_distribution.len) return 0; // invalid placement from the minigame, just award 0 points
    return score_distribution[placement];
}

pub fn init(sim: *simulation.Simulation, timeline: input.Timeline) !void {
    for (timeline.latest(), 0..) |inp, id| {
        if (inp.is_connected()) {
            const global_score = sim.meta.global_score[id];
            const global_score_counter = try counter.spawn(
                &sim.world,
                .{ constants.asset_resolution * 4, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(id)) },
                1,
                rl.Color.blue,
                global_score,
            );

            const local_score = scoreFromPlacement(sim.meta.minigame_placements[id]);
            std.debug.print("loc: {}\n", .{local_score});

            const local_score_counter = try counter.spawn(
                &sim.world,
                .{ constants.asset_resolution * 5, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(id)) },
                1,
                rl.Color.green,
                local_score,
            );

            _ = try sim.world.spawnWith(.{
                ecs.component.Plr{ .id = @intCast(id) },
                ecs.component.Pos{ .pos = .{ constants.asset_resolution * 4, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(id)) } },
                ecs.component.Anm{ .animation = Animation.SmashIdle, .interval = 16, .looping = true },
                ecs.component.Frk{ .left = global_score_counter, .right = local_score_counter },
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/smash_cat.png"),
                    .w = 2,
                    .h = 1,
                    .tint = constants.player_colors[id],
                },
            });
        }
    }

    try crown.init(sim, .{ 16, -10 });
}

pub fn update(sim: *simulation.Simulation, inputs: input.Timeline, invar: Invariables) !void {
    _ = invar;
    _ = inputs;

    const scores_depleted = checkScoresDepleted(sim);
    if (scores_depleted) {
        // try updatePos(sim);
        try transitionSystem(sim);
    } else {
        try depleteSystem(sim);
        // try skipSystem(sim, inputs);
    }

    try crown.update(sim);
    animator.update(&sim.world);
}

/// Incrementally depletes the current player score
fn depleteSystem(sim: *simulation.Simulation) !void {
    var query = sim.world.query(&.{ ecs.component.Plr, ecs.component.Frk }, &.{});
    while (query.next()) |_| {
        // const plr = query.get(ecs.component.Plr) catch unreachable;
        const frk = query.get(ecs.component.Frk) catch unreachable;
        const global_score_counter = frk.left.?;
        const local_score_counter = frk.right.?;
        // const ctr = sim.world.inspect(local_score_counter, ecs.component.Ctr) catch unreachable;
        _ = try counter.decrement(&sim.world, local_score_counter);
        _ = try counter.increment(&sim.world, global_score_counter);
    }
}

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

fn checkScoresDepleted(sim: *simulation.Simulation) bool {
    var query = sim.world.query(&.{ ecs.component.Plr, ecs.component.Frk }, &.{});
    while (query.next()) |_| {
        const frk = query.get(ecs.component.Frk) catch unreachable;
        const local_score_counter = frk.right.?;
        const ctr = sim.world.inspect(local_score_counter, ecs.component.Ctr) catch unreachable;
        std.debug.print("ctr: {}\n", .{ctr.count});
        if (ctr.count > 0) return false;
    }
    return true;
}

fn transitionSystem(sim: *simulation.Simulation) !void {
    sim.meta.minigame_timer += 1;

    if (sim.meta.minigame_timer < wait_time_ticks) return;

    for (sim.meta.global_score) |score| {
        if (score >= 500) {
            sim.meta.minigame_id = constants.minigame_winscreen;
            return;
        }
    }

    sim.meta.minigame_id = constants.minigame_gamewheel;
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
