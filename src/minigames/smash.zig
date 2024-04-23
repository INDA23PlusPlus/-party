const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const render = @import("../render.zig");
const input = @import("../input.zig");
const movement = @import("../physics/movement.zig");
const collision = @import("../physics/collision.zig");
const animator = @import("../animation/animator.zig");
const constants = @import("../constants.zig");

const Animation = @import("../animation/animations.zig").Animation;
const AssetManager = @import("../AssetManager.zig");
const Invariables = @import("../Invariables.zig");

const gravity = ecs.component.F32.init(1, 10);
const friction = ecs.component.F32.init(0, 1);
const max_acceleration = ecs.component.F32.init(1, 1);
const max_velocity = ecs.component.F32.init(10, 1);

const base_velocity = ecs.component.Vec2.init(0, gravity);

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

    // Platform
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = [_]i32{ 16 * 4, 16 * 15 } },
        ecs.component.Col{ .dim = [_]i32{ 16 * 24, 16 * 3 } },
        ecs.component.Tex{ .w = 24, .h = 3 },
    });

    _ = try sim.world.spawnWith(.{
        ecs.component.Plr{},
        ecs.component.Pos{ .pos = [_]i32{ constants.world_width / 2, constants.world_height / 2 } },
        ecs.component.Col{ .dim = [_]i32{ 16, 16 } },
        ecs.component.Mov{ .velocity = ecs.component.Vec2.init(1, 0) },
        ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/kattis.png") },
        ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
        ecs.component.Dir{ .facing = .East },
    });
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState, rt: Invariables) !void {
    var collisions = collision.CollisionQueue.init(rt.arena) catch @panic("collision");

    try inputSystem(&sim.world, inputs);
    movement.update(&sim.world, &collisions, rt.arena) catch @panic("movement");

    animator.update(&sim.world); // I don't think this should be here
}

pub fn gravitySystem(world: *ecs.world.World) void {
    var query = world.query(&.{ ecs.component.Plr, ecs.component.Mov }, &.{});
    while (query.next()) |_| {
        const mov = query.get(ecs.component.Mov) catch unreachable;
        _ = mov;
    }
}

fn inputSystem(world: *ecs.world.World, inputs: *const input.InputState) !void {
    var query = world.query(&.{ ecs.component.Mov, ecs.component.Plr, ecs.component.Anm }, &.{});
    while (query.next()) |_| {
        const mov = try query.get(ecs.component.Mov);
        const plr = try query.get(ecs.component.Plr);
        const state = inputs[plr.id];
        if (state.is_connected) {
            mov.velocity.set([_]i16{
                @intCast(3 * state.horizontal()),
                @intCast(3 * state.vertical()),
            });

            const anm = try query.get(ecs.component.Anm);
            if (state.horizontal() + state.vertical() != 0) {
                anm.animation = Animation.KattisRun;
                anm.interval = 8;
            } else {
                anm.animation = Animation.KattisIdle;
                anm.interval = 16;
            }
        }
    }
}
