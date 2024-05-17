const std = @import("std");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const render = @import("../render.zig");
const audio = @import("../audio.zig");
const input = @import("../input.zig");
const movement = @import("../physics/movement.zig");
const collision = @import("../physics/collision.zig");
const animator = @import("../animation/animator.zig");
const Animation = @import("../animation/animations.zig").Animation;
const constants = @import("../constants.zig");

const AssetManager = @import("../AssetManager.zig");
const AudioManager = @import("../AudioManager.zig");
const Invariables = @import("../Invariables.zig");

const left_texture_offset = [_]i32{ -5, -10 };
const right_texture_offset = [_]i32{ -21, -10 };

pub fn init(sim: *simulation.Simulation, timeline: input.Timeline) !void {
    sim.meta.minigame_counter = @intCast(timeline.connectedPlayerCount());

    sim.meta.minigame_timer = 16;

    // Background
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{},
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/tron_map.png"),
            .w = 32,
            .h = 18,
        },
    });

    // Walls
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{},
        ecs.component.Col{ .dim = [_]i32{ 16, 16 * 18 } },
    });
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{},
        ecs.component.Col{ .dim = [_]i32{ 16 * 32, 16 } },
    });
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = [_]i32{ 16 * 31, 0 } },
        ecs.component.Col{ .dim = [_]i32{ 16, 16 * 18 } },
    });
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = [_]i32{ 0, 16 * 17 } },
        ecs.component.Col{ .dim = [_]i32{ 16 * 32, 16 } },
    });

    // Players
    for (timeline.latest(), 0..) |plr, i| {
        if (plr.dpad == .Disconnected) continue;

        const id: u32 = @intCast(i);
        const x: i32 = @intCast(64 + (i % 4) * 64);
        const y: i32 = @intCast(64 + (i / 4) * 64);

        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = id },
            ecs.component.Pos{ .pos = [_]i32{ x, y } },
            ecs.component.Col{ .dim = [_]i32{ 16, 16 } },
            ecs.component.Mov{ .velocity = ecs.component.Vec2.init(1, 0) },
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/cat_portrait.png"),
                .tint = constants.player_colors[id],
                .flip_horizontal = true,
            },
            ecs.component.Anm{
                .animation = Animation.CatPortrait,
                .interval = 8,
                .looping = true,
            },
            ecs.component.Dir{ .facing = .East },
        });

        sim.meta.minigame_placements[id] = 0; // Everyone's a winner by default
    }
}

pub fn update(sim: *simulation.Simulation, timeline: input.Timeline, _: Invariables) !void {
    audio.update(&sim.world);

    // Set move direction.
    inputSystem(&sim.world, timeline);

    try trailSystem(sim);

    // Set positions for collisions.
    repositionSystem(sim);

    // Kills players.
    try deathSystem(sim);

    // Set move velocity for animation.
    velocitySystem(sim);

    // Set facing of players.
    playerFacingSystem(sim);

    // Set subpositions of sprites.
    animationSystem(sim);

    // Animate sprites.
    animator.update(&sim.world);

    if (sim.meta.ticks_elapsed % sim.meta.minigame_timer == 0) {
        _ = try sim.world.spawnWith(.{ecs.component.Snd{
            .sound_hash = comptime AudioManager.path_to_key("assets/audio/walk.wav"),
        }});

        var sounds = sim.world.query(&.{}, ecs.component.components);

        while (sounds.next()) |entity| {
            sim.world.kill(entity);
        }
    }

    if (sim.meta.minigame_counter <= 1) sim.meta.minigame_id = constants.minigame_scoreboard;
}

fn inputSystem(world: *ecs.world.World, timeline: input.Timeline) void {
    const inputs = timeline.latest();
    var query = world.query(&.{
        ecs.component.Plr,
        ecs.component.Dir,
    }, &.{});

    while (query.next()) |_| {
        const plr = query.get(ecs.component.Plr) catch unreachable;

        const state = inputs[plr.id];

        if (!state.is_connected()) continue;

        const dir = query.get(ecs.component.Dir) catch unreachable;

        if (state.dpad == .West) dir.facing = .West;
        if (state.dpad == .East) dir.facing = .East;
        if (state.dpad == .North) dir.facing = .North;
        if (state.dpad == .South) dir.facing = .South;
    }
}

fn velocitySystem(sim: *simulation.Simulation) void {
    if (sim.meta.ticks_elapsed % sim.meta.minigame_timer != 0) return;

    var query = sim.world.query(&.{
        ecs.component.Dir,
        ecs.component.Mov,
    }, &.{});

    while (query.next()) |_| {
        const dir = query.get(ecs.component.Dir) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;

        switch (dir.facing) {
            .West => if (mov.velocity.vector[0] <= 0) mov.velocity.set([_]i16{ -1, 0 }),
            .East => if (mov.velocity.vector[0] >= 0) mov.velocity.set([_]i16{ 1, 0 }),
            .North => if (mov.velocity.vector[1] <= 0) mov.velocity.set([_]i16{ 0, -1 }),
            .South => if (mov.velocity.vector[1] >= 0) mov.velocity.set([_]i16{ 0, 1 }),
            else => {},
        }
    }
}

fn playerFacingSystem(sim: *simulation.Simulation) void {
    if (sim.meta.ticks_elapsed % sim.meta.minigame_timer != 0) return;

    var query = sim.world.query(&.{
        ecs.component.Plr,
        ecs.component.Tex,
        ecs.component.Mov,
    }, &.{});

    while (query.next()) |_| {
        const tex = query.get(ecs.component.Tex) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;

        if (mov.velocity.vector[0] < 0) tex.flip_horizontal = false;
        if (mov.velocity.vector[0] > 0) tex.flip_horizontal = true;
    }
}

fn repositionSystem(sim: *simulation.Simulation) void {
    if (sim.meta.ticks_elapsed % sim.meta.minigame_timer != 0) return;

    var query = sim.world.query(&.{
        ecs.component.Pos,
        ecs.component.Mov,
    }, &.{});

    while (query.next()) |_| {
        const pos = query.get(ecs.component.Pos) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;

        pos.pos += mov.velocity.toInts() * [2]i32{ constants.asset_resolution, constants.asset_resolution };
    }
}

fn animationSystem(sim: *simulation.Simulation) void {
    if (sim.meta.ticks_elapsed % sim.meta.minigame_timer == 0) {
        var query = sim.world.query(&.{
            ecs.component.Tex,
            ecs.component.Mov,
        }, &.{});

        while (query.next()) |_| {
            const tex = query.get(ecs.component.Tex) catch unreachable;

            tex.subpos = .{ 0, 0 };
        }

        return;
    }

    var query = sim.world.query(&.{
        ecs.component.Tex,
        ecs.component.Mov,
    }, &.{});

    while (query.next()) |_| {
        const tex = query.get(ecs.component.Tex) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;

        tex.subpos += mov.velocity.toInts();
    }
}

fn trailSystem(sim: *simulation.Simulation) !void {
    if (sim.meta.ticks_elapsed % sim.meta.minigame_timer != 0) return;

    var despawn_query = sim.world.query(&.{
        ecs.component.Ctr,
        ecs.component.Tex,
    }, &.{});

    while (despawn_query.next()) |entity| {
        const ctr = despawn_query.get(ecs.component.Ctr) catch unreachable;
        const tex = despawn_query.get(ecs.component.Tex) catch unreachable;

        if (ctr.count == 0) sim.world.kill(entity) else ctr.count -= 1;

        const alpha: u8 = @intCast((255 * ctr.count) / (18 - sim.meta.minigame_counter));

        tex.tint.a = alpha;
    }

    var spawn_query = sim.world.query(&.{
        ecs.component.Plr,
        ecs.component.Pos,
    }, &.{});

    while (spawn_query.next()) |_| {
        const pos = spawn_query.get(ecs.component.Pos) catch unreachable;

        _ = try sim.world.spawnWith(.{
            ecs.component.Pos{ .pos = pos.pos },
            ecs.component.Col{ .dim = [_]i32{ 16, 16 } },
            ecs.component.Ctr{ .count = 18 - sim.meta.minigame_counter },
            ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/tron_skull.png") },
            ecs.component.Anm{
                .animation = .TronSkull,
                .looping = true,
                .interval = 8,
                .subframe = @intCast((sim.meta.ticks_elapsed % 32)), // sync animations
            },
        });
    }
}

fn deathSystem(sim: *simulation.Simulation) !void {
    if (sim.meta.ticks_elapsed % sim.meta.minigame_timer != 0) return;

    var player_query = sim.world.query(&.{
        ecs.component.Plr,
        ecs.component.Pos,
        ecs.component.Col,
    }, &.{});

    var dead_players: u32 = 0;

    while (player_query.next()) |player| {
        const player_pos = player_query.get(ecs.component.Pos) catch unreachable;
        const player_col = player_query.get(ecs.component.Col) catch unreachable;

        var collidable_query = sim.world.query(&.{
            ecs.component.Pos,
            ecs.component.Col,
        }, &.{});

        while (collidable_query.next()) |entity| {
            if (player.eq(entity)) continue;

            const collidable_pos = collidable_query.get(ecs.component.Pos) catch unreachable;
            const collidable_col = collidable_query.get(ecs.component.Col) catch unreachable;

            if (collision.intersects(player_pos, player_col, collidable_pos, collidable_col)) {
                dead_players += 1;
                sim.meta.minigame_counter -= 1;
                sim.world.demote(player, &.{
                    ecs.component.Mov,
                    ecs.component.Tex,
                    ecs.component.Anm,
                    ecs.component.Dir,
                });

                break;
            }
        }
    }

    var dead_player_query = sim.world.query(&.{
        ecs.component.Plr,
    }, &.{
        ecs.component.Mov,
        ecs.component.Tex,
        ecs.component.Anm,
        ecs.component.Dir,
    });

    while (dead_player_query.next()) |player| {
        const plr = dead_player_query.get(ecs.component.Plr) catch unreachable;

        sim.meta.minigame_placements[plr.id] = sim.meta.minigame_counter + dead_players - 1;
        sim.world.kill(player);
    }

    if (dead_players > 0) {
        _ = try sim.world.spawnWith(.{ecs.component.Snd{
            .sound_hash = comptime AudioManager.path_to_key("assets/audio/death.wav"),
        }});
    }
}
