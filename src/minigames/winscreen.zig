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
    sim.meta.minigame_counter = @intCast(timeline.connectedPlayerCount());
    // background
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
    // podium
    _ = try spawnPodium(sim);
    // players
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

    // text
    _ = try sim.world.spawnWith(.{ ecs.component.Pos{ .pos = .{ constants.world_width / 2, constants.world_height - 100 } }, ecs.component.Tex{
        .texture_hash = AssetManager.pathHash("assets/press_any_button.png"),
        .w = 11,
        .h = 1,
        .u = 0,
        .v = 0,
        .subpos = .{ -5 * 16, 8 },
        .tint = rl.Color.white,
    } });
}

pub fn update(sim: *simulation.Simulation, inputs: input.Timeline, _: Invariables) !void {
    const sorted_players = sortPlayersByScore(sim);
    if (sim.meta.minigame_timer == 32) {
        if (sim.meta.minigame_counter > 0) {
            sim.meta.minigame_timer = 0;
            try placePlayer(sim, sorted_players);
        } else {
            try moveToLobby(sim, inputs);
        }
    } else {
        sim.meta.minigame_timer += 1;
    }
    try crown.update(sim);
    animator.update(&sim.world);
}

fn placePlayer(sim: *simulation.Simulation, sorted_players: [constants.max_player_count][2]u32) !void {
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
        if (state.is_connected()) {
            if (state.button_a == .Pressed or state.button_b == .Pressed) {
                for (&sim.meta.global_score) |*score| {
                    score.* = 0;
                }
                sim.meta.minigame_id = constants.minigame_lobby;
            }
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

/// Returns a sorted array of player (score, id) pairs.
fn sortPlayersByScore(sim: *simulation.Simulation) [constants.max_player_count][2]u32 {
    const scores = sim.meta.global_score;
    var scores_and_ids: [constants.max_player_count][2]u32 = .{.{ undefined, undefined }} ** constants.max_player_count;
    for (scores, 0..scores.len) |score, id| {
        scores_and_ids[id] = .{ score, @as(u32, @intCast(id)) };
    }
    std.mem.sort([2]u32, &scores_and_ids, {}, lessThanFn);
    return scores_and_ids;
}

fn lessThanFn(_: void, a: [2]u32, b: [2]u32) bool {
    return a[0] > b[0];
}
