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

// Temporary globals.
var prng = std.rand.DefaultPrng.init(0);
const rand = prng.random();

pub fn init(sim: *simulation.Simulation, _: *const input.InputState) !void {
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{},
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/tron_map.png"),
            .w = 32,
            .h = 18,
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
        ecs.component.Mov{ .velocity = ecs.component.Vec2.init(1, 0) },
        ecs.component.Col{ .dim = [_]i32{ 16, 16 } },
        ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/kattis.png") },
        ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
        ecs.component.Plr{},
        ecs.component.Dir{ .facing = .East },
        ecs.component.Lnk{},
    });
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState, arena: std.mem.Allocator) !void {
    var collisions = collision.CollisionQueue.init(arena) catch @panic("could not initialize collision queue");

    try inputSystem(&sim.world, inputs);
    try directionSystem(&sim.world);
    movement.update(&sim.world, &collisions, arena) catch @panic("movement system failed");
    animator.update(&sim.world);
}

fn inputSystem(world: *ecs.world.World, inputs: *const input.InputState) !void {
    var query = world.query(&.{
        ecs.component.Dir,
        ecs.component.Plr,
        ecs.component.Mov,
        ecs.component.Pos,
    }, &.{});
    while (query.next()) |_| {
        const pos = query.get(ecs.component.Pos) catch unreachable;
        const rem = @rem(pos.pos, [_]i32{ 16, 16 });
        const vec = rem != @Vector(2, i32){ 0, 0 };

        if (@reduce(.Or, vec)) {
            continue;
        }

        const dir = query.get(ecs.component.Dir) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const state = inputs[plr.id];

        if (state.is_connected) {
            if (state.left.is_down and dir.facing != .East) mov.velocity = ecs.component.Vec2.init(-3, 0).div(4);
            if (state.right.is_down and dir.facing != .West) mov.velocity = ecs.component.Vec2.init(3, 0).div(4);
            if (state.up.is_down and dir.facing != .South) mov.velocity = ecs.component.Vec2.init(0, -3).div(4);
            if (state.down.is_down and dir.facing != .North) mov.velocity = ecs.component.Vec2.init(0, 3).div(4);
        }
    }
}

fn directionSystem(world: *ecs.world.World) !void {
    var query = world.query(&.{ ecs.component.Dir, ecs.component.Mov }, &.{});
    while (query.next()) |_| {
        const dir = query.get(ecs.component.Dir) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;

        if (mov.velocity.vector[0] < 0) dir.facing = .West;
        if (mov.velocity.vector[0] > 0) dir.facing = .East;
        if (mov.velocity.vector[1] < 0) dir.facing = .North;
        if (mov.velocity.vector[1] > 0) dir.facing = .South;
    }
}
