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
const text_tooling = @import("../counter.zig");

const score_text_color = 0xFFCC99FF;

pub fn init(sim: *simulation.Simulation, timeline: input.Timeline) !void {
    _ = timeline;
    sim.meta.minigame_counter = 8;
    std.debug.print("Press B to go to lobby", .{});
    for (0..8) |id| {
        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = @intCast(id) },
            ecs.component.Pos{ .pos = .{ constants.asset_resolution * -4, constants.asset_resolution * -4 } },
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/smash_cat.png"),
                .w = 2,
                .h = 1,
                .tint = constants.player_colors[id],
            },
            ecs.component.Anm{ .animation = Animation.SmashIdle, .interval = 16, .looping = true },
        });
    }
    // for (timeline.latest(), 0..) |inp, id| {
    //     if (inp.is_connected()) {
    //         _ = try sim.world.spawnWith(.{
    //             ecs.component.Plr{ .id = @intCast(id) },
    //             ecs.component.Pos{ .pos = .{ constants.asset_resolution * -4, constants.asset_resolution * -4 } },
    //             ecs.component.Tex{
    //                 .texture_hash = AssetManager.pathHash("assets/smash_cat.png"),
    //                 .w = 2,
    //                 .h = 1,
    //                 .tint = constants.player_colors[id],
    //             },
    //             ecs.component.Anm{ .animation = Animation.SmashIdle, .interval = 16, .looping = true },
    //         });
    //     }
    // }

    try crown.init(sim, .{ 0, -5 });
}

pub fn update(sim: *simulation.Simulation, inputs: input.Timeline, _: Invariables) !void {
    const sorted_players = sortPlayerAterScore(sim);
    if (sim.meta.minigame_timer == 30) {
        if (sim.meta.minigame_counter > 0) {
            try placePlayer(sim, sorted_players);
            sim.meta.minigame_timer = 0;
        } else {
            try moveToLobby(sim, inputs);
        }
    } else {
        sim.meta.minigame_timer += 1;
    }
}

fn placePlayer(sim: *simulation.Simulation, sorted_players: [8][2]u32) !void {
    const player = sorted_players[sim.meta.minigame_counter - 1];
    var query = sim.world.query(&.{ ecs.component.Plr, ecs.component.Pos }, &.{});
    while (query.next()) |_| {
        const plr = try query.get(ecs.component.Plr);
        const pos = try query.get(ecs.component.Pos);
        if (plr.id == player[1]) {
            if (sim.meta.minigame_counter == 1) {
                pos.pos = .{ constants.world_width / 2 - 16, constants.asset_resolution * 2 };
                break;
            } else if (sim.meta.minigame_counter == 2) {
                pos.pos = .{ constants.world_width / 2 - 16 * 3, constants.asset_resolution * 3 };
                break;
            } else if (sim.meta.minigame_counter == 3) {
                pos.pos = .{ constants.world_width / 2 + 16, constants.asset_resolution * 3 + 5 };
                break;
            } else {
                pos.pos = .{ constants.asset_resolution * 6 + (constants.asset_resolution * 3) * ((@as(i32, @intCast(sim.meta.minigame_counter)) - 3)), constants.asset_resolution * 10 };

                break;
            }
        }
    }
    sim.meta.minigame_counter -= 1;
}

fn moveToLobby(sim: *simulation.Simulation, inputs: input.Timeline) !void {
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

fn sortPlayerAterScore(sim: *simulation.Simulation) [8][2]u32 {
    //Sort player afterscore
    //Returns an array of two place arrays where index 0 is the score of the player and index 1 is the player id
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
