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
const text_tooling = @import("../text_tool.zig");

const score_text_color = 0xFFCC99FF;

pub fn init(sim: *simulation.Simulation, timeline: input.Timeline) !void {
    std.debug.print("Press B to go to lobby", .{});
    for (timeline.latest(), 0..) |inp, id| {
        if (inp.is_connected()) {
            _ = try sim.world.spawnWith(.{
                ecs.component.Plr{ .id = @intCast(id) },
                ecs.component.Pos{ .pos = .{ constants.asset_resolution * 4, constants.asset_resolution * 4 } },
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/smash_cat.png"),
                    .w = 2,
                    .h = 1,
                    .tint = constants.player_colors[id],
                },
                ecs.component.Anm{ .animation = Animation.SmashIdle, .interval = 16, .looping = true },
            });
        }
    }

    try crown.init(sim, .{ 0, -5 });
}

pub fn update(sim: *simulation.Simulation, inputs: input.Timeline, _: Invariables) !void {
    try moveToNextMinigame(sim, inputs);
}

fn moveToNextMinigame(sim: *simulation.Simulation, inputs: input.Timeline) !void {
    const latest = inputs.latest();
    var query = sim.world.query(&.{ecs.component.Plr}, &.{});
    while (query.next()) |_| {
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const id = plr.id;
        const state = latest[id];
        if (state.button_b == .Pressed) {
            sim.meta.minigame_id = 2;
        }
    }
}

fn updatePos(sim: *simulation.Simulation) [8][2]u32 {
    const scores = sim.meta.global_score;
    var scores_with_id: [8][2]u32 = .{ .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined }, .{ undefined, undefined } };
    for (scores, 0..scores.len) |score, id| {
        scores_with_id[id] = .{ score, @as(u32, @intCast(id)) };
    }
    std.mem.sort([2]u32, &scores_with_id, {}, lessThanFn);
    return scores_with_id;
    // var query = sim.world.query(&.{ ecs.component.Plr, ecs.component.Pos, ecs.component.Lnk }, &.{});
    // while (query.next()) |_| {
    //     const plr = query.get(ecs.component.Plr) catch unreachable;
    //     const pos = query.get(ecs.component.Pos) catch unreachable;
    //     const lnk = query.get(ecs.component.Lnk) catch unreachable;

    //     for (scores_with_id, 8..0) |score_with_id, placement| {
    //         if (plr.id == score_with_id[1]) {
    //             if (placement == 0) {
    //                 const ctr_pos = sim.world.inspect(lnk.child.?, ecs.component.Pos) catch unreachable;
    //                 pos.pos = .{ constants.world_width_tiles / 2, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(placement)) };
    //                 ctr_pos.pos = .{ constants.asset_resolution * 4, 16 + (16 + constants.asset_resolution) * @as(i32, @intCast(placement)) };
    //             }
    //         }
    //     }
    // }
}

fn lessThanFn(_: void, a: [2]u32, b: [2]u32) bool {
    return a[0] < b[0];
}
