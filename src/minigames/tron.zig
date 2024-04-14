const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const render = @import("../render.zig");
const AssetManager = @import("../AssetManager.zig");
const input = @import("../input.zig");
const collide = @import("../physics/collide.zig");
const animator = @import("../animation/animator.zig");
const Animation = @import("../animation/animations.zig").Animation;

// Temporary global.
var collisions: collide.CollisionQueue = undefined;

pub fn init(sim: *simulation.Simulation) !void {
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{},
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/tron_map.png"),
            .tiles_x = 32,
            .tiles_y = 18,
        },
    });

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

    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = [_]i32{ 16, 16 } },
        ecs.component.Mov{},
        ecs.component.Col{ .dim = [_]i32{ 16, 16 } },
        ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/kattis.png") },
        ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
        ecs.component.Plr{},
    });

    collisions = collide.CollisionQueue.init(std.heap.page_allocator);
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState) !void {
    try inputSystem(&sim.world, inputs);
    collide.movementSystem(&sim.world, &collisions) catch @panic("movement system failed");
    animator.update(&sim.world);
}

fn inputSystem(world: *ecs.world.World, inputs: *const input.InputState) !void {
    var query = world.query(&.{ ecs.component.Mov, ecs.component.Plr }, &.{});
    while (query.next()) |_| {
        const mov = query.get(ecs.component.Mov) catch unreachable;
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const state = inputs[plr.id];
        if (state.is_connected) {
            mov.velocity.set([_]i16{
                @intCast(3 * state.horizontal()),
                @intCast(3 * state.vertical()),
            });
        }
    }
}
