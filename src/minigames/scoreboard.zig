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

const score_distribution: [constants.max_player_count]u32 = .{ 50, 20, 10, 0, 0, 0, 0, 0 }; // completely arbitrary score values, open to change
const score_decrease_speed = 1; // how much the score decreases every tick
const wait_time_ticks = 5 * constants.ticks_per_second; // time before switching minigame
const score_text_color = 0xFFCC99FF;

fn scoreFromPlacement(placement: u32) u32 {
    if (placement >= score_distribution.len) return 0; // invalid placement from the minigame, just award 0 points
    return score_distribution[placement];
}

pub fn init(sim: *simulation.Simulation, timeline: input.Timeline) !void {
    for (timeline.latest(), 0..) |inp, id| {
        if (inp.is_connected()) {
            const placement = sim.meta.minigame_placements[id];
            const score = scoreFromPlacement(placement);
            const score_counter = try sim.world.spawnWith(.{
                ecs.component.Pos{ .pos = .{ constants.asset_resolution * 4, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(id)) } },
                ecs.component.Ctr{ .count = score, .id = @intCast(id) },
                ecs.component.TextDeprecated{ .color = score_text_color, .string = "???", .font_size = 18, .subpos = .{ 64, 6 } },
            });
            _ = try sim.world.spawnWith(.{
                ecs.component.Plr{ .id = @intCast(id) },
                ecs.component.Pos{ .pos = .{ constants.asset_resolution * 4, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(id)) } },
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/smash_cat.png"),
                    .w = 2,
                    .h = 1,
                    .tint = constants.player_colors[id],
                },
                ecs.component.Anm{ .animation = Animation.SmashIdle, .interval = 16, .looping = true },
                ecs.component.Lnk{ .child = score_counter },
            });
        }
    }
    try crown.init(sim, .{ 0, -5 });
    // timer responsible for changing minigame
    _ = try sim.world.spawnWith(.{ecs.component.Ctr{ .count = wait_time_ticks }});
}

pub fn update(sim: *simulation.Simulation, inputs: input.Timeline, invar: Invariables) !void {
    _ = invar;

    try instantDepleteScore(sim, inputs);
    const scores_depleted = try checkScoresDepleted(sim);
    if (scores_depleted) {
        try updatePos(sim);
        try tickNextGameTimer(sim);
    } else {
        try depleteScores(sim);
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
        const txt = sim.world.inspect(score_counter, ecs.component.TextDeprecated) catch unreachable;
        const id = plr.id;
        const delta = @min(score_decrease_speed, ctr.count);
        ctr.count -= delta;
        sim.meta.global_score[id] += delta;
        txt.string = rl.textFormat("%d +%d", .{ sim.meta.global_score[id], ctr.count });
    }
}

fn instantDepleteScore(sim: *simulation.Simulation, inputs: input.Timeline) !void {
    const latest = inputs.latest();
    var query = sim.world.query(&.{ ecs.component.Plr, ecs.component.Lnk }, &.{});
    while (query.next()) |_| {
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const lnk = query.get(ecs.component.Lnk) catch unreachable;
        const score_counter = lnk.child.?; // should not be null

        const ctr = sim.world.inspect(score_counter, ecs.component.Ctr) catch unreachable;
        const txt = sim.world.inspect(score_counter, ecs.component.TextDeprecated) catch unreachable;

        const id = plr.id;

        const state = latest[id];

        if (state.button_b == .Pressed) {
            sim.meta.global_score[id] += ctr.count;
            ctr.count = 0;
            txt.string = "DONE"; // Debug
        }
    }
}

fn checkScoresDepleted(sim: *simulation.Simulation) !bool {
    var query = sim.world.query(&.{ ecs.component.Ctr, ecs.component.TextDeprecated }, &.{});
    while (query.next()) |_| {
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        if (ctr.count > 0) return false;
    }
    return true;
}

fn tickNextGameTimer(sim: *simulation.Simulation) !void {
    var query = sim.world.query(&.{ecs.component.Ctr}, &.{ecs.component.TextDeprecated});
    while (query.next()) |_| {
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        if (ctr.count > 0) {
            ctr.count -= 1;
            return;
        }
        for (sim.meta.global_score) |score| {

            //Future TODO Move value to metadata or constants dpeending on if the player can shose the amount of round/hisgh score
            if (score >= 500) {
                sim.meta.minigame_id = 5;
                break;
            } else {
                sim.meta.minigame_id = constants.minigame_gamewheel;
            }
        }
    }
}

fn updatePos(sim: *simulation.Simulation) !void {
    const scores = sim.meta.global_score;
    var scores_with_id: [8][2]u32 = .{ .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined } };
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
