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

const score_distribution: [constants.max_player_count]u32 = .{ 20, 10, 5, 2, 0, 0, 0, 0 }; // completely arbitrary score values, open to change
const score_decrease_speed = 1; // how much the score decreases every tick
const wait_time_ticks = 3 * constants.ticks_per_second; // time before switching minigame
const score_text_color = 0xFFCC99FF;

fn scoreFromPlacement(placement: u32) u32 {
    if (placement >= score_distribution.len) return 0; // invalid placement from the minigame, just award 0 points
    return score_distribution[placement];
}

pub fn init(sim: *simulation.Simulation, _: input.Timeline) !void {
    for (0..constants.max_player_count) |id| {
        const placement = sim.meta.minigame_placements[id];
        const score = scoreFromPlacement(placement);
        const score_counter = try sim.world.spawnWith(.{
            ecs.component.Pos{ .pos = .{ constants.asset_resolution * 4, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(id)) } },
            ecs.component.Ctr{ .count = score, .id = @intCast(id) },
            ecs.component.Txt{ .color = score_text_color, .string = "???", .font_size = 18, .subpos = .{ 64, 6 } },
        });
        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = @intCast(id) },
            ecs.component.Pos{ .pos = .{ constants.asset_resolution * 4, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(id)) } },
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/kattis.png"),
                .tint = constants.player_colors[id],
            },
            ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
            ecs.component.Lnk{ .child = score_counter },
        });
    }
    try crown.init(sim, .{ 0, -5 });
    // timer responsible for changing minigame
    _ = try sim.world.spawnWith(.{ecs.component.Ctr{ .count = wait_time_ticks }});
}

pub fn update(sim: *simulation.Simulation, inputs: input.Timeline, invar: Invariables) !void {
    _ = inputs;
    _ = invar;

    try depleteScores(sim);
    const scores_depleted = try checkScoresDepleted(sim);
    if (scores_depleted) {
        try tickNextGameTimer(sim);
    }

    try crown.update(sim);
    animator.update(&sim.world);
}

fn depleteScores(sim: *simulation.Simulation) !void {
    var query = sim.world.query(&.{ ecs.component.Plr, ecs.component.Lnk }, &.{});
    while (query.next()) |_| {
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const lnk = query.get(ecs.component.Lnk) catch unreachable;
        const score_counter = lnk.child.?; // should not be null
        const ctr = sim.world.inspect(score_counter, ecs.component.Ctr) catch unreachable;
        const txt = sim.world.inspect(score_counter, ecs.component.Txt) catch unreachable;
        const id = plr.id;
        const delta = @min(score_decrease_speed, ctr.count);
        ctr.count -= delta;
        sim.meta.global_score[id] += delta;
        txt.string = rl.textFormat("%d +%d", .{ sim.meta.global_score[id], ctr.count });
    }
}
fn checkScoresDepleted(sim: *simulation.Simulation) !bool {
    var query = sim.world.query(&.{ ecs.component.Ctr, ecs.component.Txt }, &.{});
    while (query.next()) |_| {
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        if (ctr.count > 0) return false;
    }
    return true;
}

fn tickNextGameTimer(sim: *simulation.Simulation) !void {
    var query = sim.world.query(&.{ecs.component.Ctr}, &.{ecs.component.Txt});
    while (query.next()) |_| {
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        if (ctr.count > 0) {
            ctr.count -= 1;
            return;
        }
        sim.meta.minigame_id = 4;
    }
}

// idk what this is ?

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
