const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const render = @import("../render.zig");
const AssetManager = @import("../AssetManager.zig");
const input = @import("../input.zig");
const movement = @import("../physics/movement.zig");
const collision = @import("../physics/collision.zig");
const animator = @import("../animation/animator.zig");
const Animation = @import("../animation/animations.zig").Animation;
const constants = @import("../constants.zig");

pub fn init(sim: *simulation.Simulation, _: *const input.InputState) !void {
    sim.meta.minigame_ticks_per_update = 16;

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
    _ = try sim.world.spawnWith(.{
        ecs.component.Plr{},
        ecs.component.Pos{ .pos = [_]i32{ 48, 16 } },
        ecs.component.Col{ .dim = [_]i32{ 16, 16 } },
        ecs.component.Mov{ .velocity = ecs.component.Vec2.init(1, 0) },
        ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/kattis.png") },
        ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
        ecs.component.Dir{ .facing = .East },
    });
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState, arena: std.mem.Allocator) !void {
    _ = arena;

    // Set move direction.
    inputSystem(&sim.world, inputs);

    try trailSystem(sim);

    // Set positions for collisions.
    repositionSystem(sim);

    // Kills players.
    deathSystem(sim);

    // Set move velocity for animation.
    velocitySystem(sim);

    // Set facing of players.
    playerFacingSystem(sim);

    // Set subpositions of sprites.
    animationSystem(sim);

    // Animate sprites.
    animator.update(&sim.world);
}

fn inputSystem(world: *ecs.world.World, inputs: *const input.InputState) void {
    var query = world.query(&.{
        ecs.component.Plr,
        ecs.component.Dir,
    }, &.{});

    while (query.next()) |_| {
        const plr = query.get(ecs.component.Plr) catch unreachable;

        const state = inputs[plr.id];

        if (!state.is_connected) continue;

        const dir = query.get(ecs.component.Dir) catch unreachable;

        if (state.button_left.is_down) dir.facing = .West;
        if (state.button_right.is_down) dir.facing = .East;
        if (state.button_up.is_down) dir.facing = .North;
        if (state.button_down.is_down) dir.facing = .South;
    }
}

fn velocitySystem(sim: *simulation.Simulation) void {
    if (sim.meta.ticks_elapsed % sim.meta.minigame_ticks_per_update != 0) return;

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
    if (sim.meta.ticks_elapsed % sim.meta.minigame_ticks_per_update != 0) return;

    var query = sim.world.query(&.{
        ecs.component.Plr,
        ecs.component.Tex,
        ecs.component.Mov,
    }, &.{});

    while (query.next()) |_| {
        const tex = query.get(ecs.component.Tex) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;

        if (mov.velocity.vector[0] < 0) tex.flip_horizontal = true;
        if (mov.velocity.vector[0] > 0) tex.flip_horizontal = false;
    }
}

fn repositionSystem(sim: *simulation.Simulation) void {
    if (sim.meta.ticks_elapsed % sim.meta.minigame_ticks_per_update != 0) return;

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
    if (sim.meta.ticks_elapsed % sim.meta.minigame_ticks_per_update == 0) {
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
    if (sim.meta.ticks_elapsed % sim.meta.minigame_ticks_per_update != 0) return;

    var spawn_query = sim.world.query(&.{
        ecs.component.Plr,
        ecs.component.Pos,
    }, &.{});

    while (spawn_query.next()) |_| {
        const pos = spawn_query.get(ecs.component.Pos) catch unreachable;

        _ = try sim.world.spawnWith(.{
            ecs.component.Pos{ .pos = pos.pos },
            ecs.component.Col{ .dim = [_]i32{ 16, 16 } },
            ecs.component.Ctr{},
            ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/tron_skull.png") },
            ecs.component.Anm{
                .animation = .TronSkull,
                .looping = true,
                .interval = 16,
                .subframe = @intCast((sim.meta.ticks_elapsed % 64)), // sync animations
            },
        });
    }

    var despawn_query = sim.world.query(&.{
        ecs.component.Ctr,
        ecs.component.Tex,
    }, &.{});

    while (despawn_query.next()) |entity| {
        const ctr = despawn_query.get(ecs.component.Ctr) catch unreachable;
        const Tex = despawn_query.get(ecs.component.Tex) catch unreachable;

        if (ctr.counter > 10) sim.world.kill(entity) else ctr.counter += 1;

        Tex.tint.a -= 15;
    }
}

fn deathSystem(sim: *simulation.Simulation) void {
    if (sim.meta.ticks_elapsed % sim.meta.minigame_ticks_per_update != 0) return;

    var player_query = sim.world.query(&.{
        ecs.component.Plr,
        ecs.component.Pos,
        ecs.component.Col,
    }, &.{});

    while (player_query.next()) |ent1| {
        const player_pos = player_query.get(ecs.component.Pos) catch unreachable;
        const player_col = player_query.get(ecs.component.Col) catch unreachable;

        var collidable_query = sim.world.query(&.{
            ecs.component.Pos,
            ecs.component.Col,
        }, &.{});

        while (collidable_query.next()) |ent2| {
            if (ent1.eq(ent2)) continue;

            const collidable_pos = collidable_query.get(ecs.component.Pos) catch unreachable;
            const collidable_col = collidable_query.get(ecs.component.Col) catch unreachable;

            if (collision.intersects(player_pos, player_col, collidable_pos, collidable_col)) {
                sim.world.kill(ent1);
                break;
            }
        }
    }
}
