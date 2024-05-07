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

// Scoreboard:
// Deplete local score and add to global score
// Change minigame once all scores are depleted

// TODO:
// - Deplete the scores in order
// - Speed up the score animation as it goes on
// - Allow pressing button to skip score animation

const score_distribution: [constants.max_player_count]u32 = .{ 1000, 800, 600, 500, 150, 100, 75, 250 }; // completely arbitrary score values, open to change
const score_decrease_speed = 10; // how much the score decreases every tick
const wait_time_ticks = 3 * constants.ticks_per_second; // time before switching minigame
const switching_timer_id = 100;
const score_text_color = 0xFFCC99FF;

fn scoreFromPlacement(placement: u32) u32 {
    if (placement >= score_distribution.len) return 0; // bad value
    return score_distribution[placement];
}

pub fn init(sim: *simulation.Simulation, _: input.Timeline) !void {
    for (0..constants.max_player_count) |id| {
        // spawn player avatar
        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = @intCast(id) },
            ecs.component.Pos{ .pos = .{ constants.asset_resolution * 4, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(id)) } },
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/kattis.png"),
                .tint = constants.player_colors[id],
            },
            ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
        });
        // spawn score counter
        const placement = sim.meta.minigame_placements[id];
        const score = scoreFromPlacement(placement);
        _ = try sim.world.spawnWith(.{
            ecs.component.Pos{ .pos = .{ constants.asset_resolution * 4, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(id)) } },
            ecs.component.Ctr{ .count = score, .id = @intCast(id) },
            ecs.component.Txt{ .color = score_text_color, .string = "???", .font_size = 18, .subpos = .{ 64, 6 } },
        });
    }
    try crown.init(sim, .{ 0, -5 });
    _ = try sim.world.spawnWith(.{
        ecs.component.Ctr{ .id = 100, .count = 20 * 60 },
    });
    _ = try sim.world.spawnWith(.{
        ecs.component.Ctr{ .id = 101, .count = 10 * 60 },
    });
    // spawn timer, responsible for changing minigame
    _ = try sim.world.spawnWith(.{ecs.component.Ctr{ .id = switching_timer_id, .count = 3 * constants.ticks_per_second }});
}

pub fn update(sim: *simulation.Simulation, inputs: input.Timeline, invar: Invariables) !void {
    _ = inputs;
    _ = invar;

    try depleteScores(sim);
    const scores_depleted = try checkScoresDepleted(sim);
    if (scores_depleted) {
        try tickNextGameTimer(sim);
    }

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
                    try updateScore(&sim.meta);
                    sim.world.kill(entity);
                    return;
                } else {
                    ctr.count -= 1;
                }
            },
            else => {},
        }
    }
    try crown.update(sim);
    animator.update(&sim.world);
}

fn depleteScores(sim: *simulation.Simulation) !void {
    var query = sim.world.query(&.{ ecs.component.Ctr, ecs.component.Txt }, &.{});
    while (query.next()) |_| {
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        const txt = query.get(ecs.component.Txt) catch unreachable;
        const delta = @min(score_decrease_speed, ctr.count);
        ctr.count -= delta;
        sim.meta.global_score[ctr.id] += delta;
        txt.string = rl.textFormat("%d +%d", .{ sim.meta.global_score[ctr.id], ctr.count });
    }
}
fn updateScore(meta: *simulation.Metadata) !void {
    for (0..constants.max_player_count) |id| {
        const mingame_placement = meta.minigame_placements[id];
        switch (mingame_placement) {
            1 => {
                meta.global_score[id] += 10;
                meta.minigame_placements[id] = undefined;
            },
            2 => {
                meta.global_score[id] += 5;
                meta.minigame_placements[id] = undefined;
            },
            3 => {
                meta.global_score[id] += 2;
                meta.minigame_placements[id] = undefined;
            },

            0 => {
                std.debug.print("Hoppsan det var fel\n", .{});
                meta.minigame_placements[id] = undefined;
            },

            else => {
                meta.minigame_placements[id] = undefined;
            },
        }
    }
}
fn checkScoresDepleted(sim: *simulation.Simulation) !bool {
    var query = sim.world.query(&.{ ecs.component.Ctr, ecs.component.Txt }, &.{});
    while (query.next()) |_| {
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        if (ctr.id >= constants.max_player_count) continue;
        if (ctr.count > 0) return false;
    }
    return true;
}

fn tickNextGameTimer(sim: *simulation.Simulation) !void {
    var query = sim.world.query(&.{ecs.component.Ctr}, &.{ecs.component.Txt});
    while (query.next()) |_| {
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        if (ctr.id != switching_timer_id) continue;
        if (ctr.count > 0) {
            ctr.count -= 1;
            return;
        }
        sim.meta.minigame_id = 4;
    }
}

fn updatePos(sim: *simulation.Simulation) !void {
    const scores = sim.meta.global_score;
    var scores_with_id: [8][2]u32 = .{ .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined } };
    for (scores, 0..scores.len) |score, id| {
        scores_with_id[id] = .{ score, @as(u32, @intCast(id)) };
    }
    topDownMergeSort(scores_with_id);
    var query = try sim.world.query(.{ ecs.component.Plr, ecs.component.Pos }, .{});
    while (query.next()) |_| {
        //TODO Make the players switch postion
        // const plr = query.get(ecs.component.Plr);

    }
}

fn topDownMergeSort(arr: [8][2]u32) !void {
    const copy = arr;
    try topDownSplitMerge(arr, 0, arr.len, copy);
}

fn topDownSplitMerge(arr: [8][2]u32, beg: usize, end: usize, copy: [8][2]u32) !void {
    if (end - beg <= 1) {
        return;
    }
    const mid = (end + beg) / 2;
    topDownSplitMerge(copy, beg, mid, arr);
    topDownSplitMerge(copy, mid, end, arr);
    topDownMerge(arr, beg, mid, end, copy);
}

fn topDownMerge(arr: [8][2]u32, beg: usize, mid: usize, end: usize, copy: [8][2]u32) !void {
    var i = beg;
    var j = mid;
    for (beg..end) |k| {
        if (i < mid and (j >= end or arr[i][0] <= arr[j][0])) {
            copy[k] = arr[i];
            i += 1;
        } else {
            copy[k] = arr[j];
            j += 1;
        }
    }
}
