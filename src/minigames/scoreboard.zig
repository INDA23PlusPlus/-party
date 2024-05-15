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
//  Deplete local score and add to global score
//  Change minigame once all scores are depleted

const depletion_interval_ticks = 2; // Time between awarding score points

pub fn init(sim: *simulation.Simulation, timeline: input.Timeline) !void {

    // Background
    _ = try sim.world.spawnWith(.{ ecs.component.Pos{}, ecs.component.Tex{
        .texture_hash = AssetManager.pathHash("assets/background_animated.png"),
        .w = constants.world_width_tiles,
        .h = constants.world_height_tiles,
        .u = 0,
        .v = 0,
    }, ecs.component.Anm{
        .animation = .ScoreboardBackground,
        .interval = 16,
    } });

    for (timeline.latest(), 0..) |inp, id| {
        if (inp.dpad == .Disconnected) continue;

        const global_score = sim.meta.global_score[id];
        const local_score: u32 = switch (sim.meta.minigame_placements[id]) {
            0 => 20,
            1 => 10,
            2 => 5,
            else => 0,
        };

        const global_score_counter = try counter.spawn(
            &sim.world,
            .{ constants.asset_resolution * 5, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(id)) },
            2,
            rl.Color.white,
            global_score,
        );

        const local_score_counter = try counter.spawn(
            &sim.world,
            .{ constants.asset_resolution * 8, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(id)) },
            2,
            rl.Color.gold,
            local_score,
        );

        sim.world.promote(global_score_counter, &.{ecs.component.Plr});
        var glob_score_plr = sim.world.inspect(global_score_counter, ecs.component.Plr) catch unreachable;
        glob_score_plr.id = @intCast(id);

        sim.world.promote(local_score_counter, &.{ecs.component.Plr});
        var loc_score_plr = sim.world.inspect(local_score_counter, ecs.component.Plr) catch unreachable;
        loc_score_plr.id = @intCast(id);

        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = @intCast(id) },
            ecs.component.Ctr{ .count = local_score },
            ecs.component.Lnk{ .child = global_score_counter },
            ecs.component.Src{},
        });

        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = @intCast(id) },
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

pub fn update(sim: *simulation.Simulation, timeline: input.Timeline, _: Invariables) !void {
    try skipSystem(sim, timeline);
    if (try depleteSystem(sim)) {
        try transitionSystem(sim);
        // try positionSystem(sim); // disabled until text is positionable
    }
    try crown.update(sim);
    animator.update(&sim.world);
}

/// Returns true if the scores have been depleted.
fn depleteSystem(sim: *simulation.Simulation) !bool {
    var depleted = true;

    var local_counter_query = sim.world.query(&.{
        ecs.component.Plr,
        ecs.component.Ctr,
        ecs.component.Lnk,
    }, &.{
        ecs.component.Str,
        ecs.component.Src,
    });

    var global_counter_query = sim.world.query(&.{
        ecs.component.Plr,
        ecs.component.Ctr,
        ecs.component.Lnk,
        ecs.component.Src,
    }, &.{
        ecs.component.Str,
    });

    if (sim.meta.minigame_counter < depletion_interval_ticks) {
        sim.meta.minigame_counter += 1;
    } else {
        sim.meta.minigame_counter = 0;

        while (local_counter_query.next()) |_| {
            const ctr = local_counter_query.get(ecs.component.Ctr) catch unreachable;
            const lnk = local_counter_query.get(ecs.component.Lnk) catch unreachable;
            if (ctr.count > 0) {
                ctr.count -= 1;
                depleted = ctr.count == 0;
                _ = try counter.decrement(&sim.world, lnk.child.?);
            }
        }

        while (global_counter_query.next()) |_| {
            const plr = global_counter_query.get(ecs.component.Plr) catch unreachable;
            const ctr = global_counter_query.get(ecs.component.Ctr) catch unreachable;
            const lnk = global_counter_query.get(ecs.component.Lnk) catch unreachable;
            if (ctr.count > 0) {
                ctr.count -= 1;
                sim.meta.global_score[plr.id] += 1;
                _ = try counter.increment(&sim.world, lnk.child.?);
            }
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

/// Instantly skips score animation if any player presses a button
fn skipSystem(sim: *simulation.Simulation, timeline: input.Timeline) !void {
    const inputs = timeline.latest();
    for (inputs) |inp| {
        if (inp.is_connected() and (inp.button_a == .Pressed or inp.button_b == .Pressed)) {
            while (!try depleteSystem(sim)) {}
        }
    }
}

fn positionSystem(sim: *simulation.Simulation) !void {
    const scores = sim.meta.global_score;

    var scores_and_ids: [constants.max_player_count][2]u32 = .{.{ undefined, undefined }} ** constants.max_player_count;
    for (scores, 0..scores.len) |score, id| {
        scores_and_ids[id] = .{ score, @as(u32, @intCast(id)) };
    }

    std.mem.sort([2]u32, &scores_and_ids, {}, lessThanFn);

    var query = sim.world.query(&.{ ecs.component.Plr, ecs.component.Pos }, &.{});
    while (query.next()) |_| {
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const pos = query.get(ecs.component.Pos) catch unreachable;
        for (scores_and_ids, 0..scores_and_ids.len) |pair, i| {
            const pid = pair[1];
            if (plr.id == pid) {
                pos.pos[1] = 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(i));
            }
        }
    }
}

fn lessThanFn(_: void, a: [2]u32, b: [2]u32) bool {
    return a[0] > b[0];
}
