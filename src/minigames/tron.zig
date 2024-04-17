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

// Temporary globals.
var collisions: collision.CollisionQueue = undefined;
var prng = std.rand.DefaultPrng.init(0);
const rand = prng.random();

pub fn init(sim: *simulation.Simulation) !void {
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{},
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/tron_map.png"),
            .tiles_x = 32,
            .tiles_y = 18,
        },
    });

    for (5..15) |i| {
        for (5..15) |j| {
            const x = blk: {
                var r: i4 = 0;
                while (r == 0) {
                    r = rand.int(i4);
                }
                break :blk r;
            };

            const y = blk: {
                var r: i4 = 0;
                while (r == 0) {
                    r = rand.int(i4);
                }
                break :blk r;
            };

            _ = try sim.world.spawnWith(.{
                ecs.component.Pos{ .pos = [_]i32{ @intCast(i * 16), @intCast(j * 16) } },
                ecs.component.Mov{ .velocity = ecs.component.Vec2.init(x, y) },
                ecs.component.Col{ .dim = [_]i32{ 16, 16 } },
                ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/kattis.png") },
            });
        }
    }

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
        ecs.component.SnakeHead{},
        ecs.component.Dir{ .facing = .East },
    });

    collisions = collision.CollisionQueue.init(std.heap.page_allocator);
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState) !void {
    try inputSystem(&sim.world, inputs);
    try directionSystem(&sim.world);
    movement.update(&sim.world, &collisions) catch @panic("movement system failed");
    collisions.clear();
    animator.update(&sim.world);
}

fn inputSystem(world: *ecs.world.World, inputs: *const input.InputState) !void {
    var query = world.query(&.{ ecs.component.Dir, ecs.component.Plr }, &.{});
    while (query.next()) |_| {
        const dir = query.get(ecs.component.Dir) catch unreachable;
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const state = inputs[plr.id];
        if (state.is_connected) {
            if (state.left.pressed()) dir.facing = .West;
            if (state.right.pressed()) dir.facing = .East;
            if (state.up.pressed()) dir.facing = .North;
            if (state.down.pressed()) dir.facing = .South;
        }
    }
}

fn tmp(world: *ecs.world.World) !void {
    var query = world.query(&.{ ecs.component.Mov, ecs.component.Pos }, &.{ecs.component.Dir});
    while (query.next()) |_| {}
}

fn directionSystem(world: *ecs.world.World) !void {
    var query = world.query(&.{ ecs.component.Dir, ecs.component.Mov, ecs.component.Pos }, &.{});
    while (query.next()) |_| {
        const dir = query.get(ecs.component.Dir) catch unreachable;
        const pos = query.get(ecs.component.Pos) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;

        const rem = @rem(pos.pos, [_]i32{ 16, 16 });
        const vec = rem != @Vector(2, i32){ 0, 0 };

        if (@reduce(.Or, vec)) {
            continue;
        }

        switch (dir.facing) {
            .West => mov.velocity = ecs.component.Vec2.init(-3, 0).div(4),
            .East => mov.velocity = ecs.component.Vec2.init(3, 0).div(4),
            .North => mov.velocity = ecs.component.Vec2.init(0, -3).div(4),
            .South => mov.velocity = ecs.component.Vec2.init(0, 3).div(4),
            else => {},
        }
    }
}
