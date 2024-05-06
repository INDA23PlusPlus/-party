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
