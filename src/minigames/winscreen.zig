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

const font_size = 1;

pub fn init(sim: *simulation.Simulation, timeline: input.Timeline) !void {
    // _ = timeline;
    sim.meta.minigame_counter = 8;
    std.debug.print("Press B to go to lobby", .{});
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = .{ 0, 0 } },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/tron_map.png"),
            .h = constants.world_height_tiles,
            .w = constants.world_width_tiles,
            .tint = rl.Color.maroon,
        },
    });
    _ = try spawnPodium(sim);
    // for (0..8) |id| {
    //     _ = try sim.world.spawnWith(.{
    //         ecs.component.Plr{ .id = @intCast(id) },
    //         ecs.component.Pos{ .pos = .{ constants.asset_resolution * -4, constants.asset_resolution * -4 } },
    //         ecs.component.Tex{
    //             .texture_hash = AssetManager.pathHash("assets/smash_cat.png"),
    //             .w = 2,
    //             .h = 1,
    //             .tint = constants.player_colors[id],
    //         },
    //         ecs.component.Anm{ .animation = Animation.SmashIdle, .interval = 16, .looping = true },
    //     });
    // }
    for (timeline.latest(), 0..) |inp, id| {
        if (inp.is_connected()) {
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
    }

    try crown.init(sim, .{ 16, -10 });
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
    try crown.update(sim);
    animator.update(&sim.world);
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
                _ = try counter.spawn(
                    &sim.world,
                    .{ constants.world_width / 2 + 2, constants.asset_resolution * 3 },
                    font_size,
                    constants.player_colors[player[1]],
                    player[0],
                );
                break;
            } else if (sim.meta.minigame_counter == 2) {
                pos.pos = .{ constants.world_width / 2 - 16 * 2, constants.asset_resolution * 3 };
                _ = try counter.spawn(
                    &sim.world,
                    .{ constants.world_width / 2 - 14, constants.asset_resolution * 4 },
                    font_size,
                    constants.player_colors[player[1]],
                    player[0],
                );

                break;
            } else if (sim.meta.minigame_counter == 3) {
                pos.pos = .{ constants.world_width / 2, constants.asset_resolution * 3 };
                _ = try counter.spawn(
                    &sim.world,
                    .{ constants.world_width / 2 + 18, constants.asset_resolution * 4 },
                    font_size,
                    constants.player_colors[player[1]],
                    player[0],
                );

                break;
            } else {
                pos.pos = .{ constants.asset_resolution * 6 + (constants.asset_resolution * 3) * ((@as(i32, @intCast(sim.meta.minigame_counter)) - 3)), constants.asset_resolution * 10 };
                _ = try counter.spawn(
                    &sim.world,
                    .{ constants.asset_resolution * 7 + (constants.asset_resolution * 3) * ((@as(i32, @intCast(sim.meta.minigame_counter)) - 3)), constants.asset_resolution * 11 },
                    font_size,
                    constants.player_colors[player[1]],
                    player[0],
                );

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
            for (&sim.meta.global_score) |*score| {
                score.* = 0;
            }

            sim.meta.minigame_id = 2;
        }
    }
}

fn spawnPodium(sim: *simulation.Simulation) !void {
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{
            .pos = .{ constants.world_width / 2, constants.asset_resolution * 3 },
        },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/podium_piece.png"),
            .h = 3,
            .w = 1,
        },
    });
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{
            .pos = .{ constants.world_width / 2 - 16, constants.asset_resolution * 4 },
        },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/podium_piece.png"),
            .h = 2,
            .w = 1,
        },
    });
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{
            .pos = .{ constants.world_width / 2 + 16, constants.asset_resolution * 4 },
        },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/podium_piece.png"),
            .h = 2,
            .w = 1,
        },
    });
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
    // v
}

fn lessThanFn(_: void, a: [2]u32, b: [2]u32) bool {
    return a[0] > b[0];
}
