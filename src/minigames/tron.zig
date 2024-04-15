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

// Temporary globals.
var collisions: collide.CollisionQueue = undefined;
var prng = std.rand.DefaultPrng.init(0);
const rand = prng.random();

var entities: [3]ecs.entity.Entity = undefined;

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
        ecs.component.Pos{ .pos = [_]i32{ 16 * 8, 16 * 8 } },
        ecs.component.Col{ .dim = [_]i32{ 16, 16 } },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/tron_map.png"),
        },
    });

    entities[0] = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = [_]i32{ 16, 16 * 3 } },
        ecs.component.Col{ .dim = [_]i32{ 16, 16 } },
        ecs.component.Mov{ .velocity = ecs.component.Vec2.init(3, 2) },
        ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/kattis.png") },
    });
    entities[1] = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = [_]i32{ 16, 16 * 4 } },
        ecs.component.Col{ .dim = [_]i32{ 16, 16 } },
        ecs.component.Mov{ .velocity = ecs.component.Vec2.init(3, 2) },
        ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/kattis.png") },
    });
    entities[2] = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = [_]i32{ 16 * 2, 16 * 3 } },
        ecs.component.Col{ .dim = [_]i32{ 16, 16 } },
        ecs.component.Mov{ .velocity = ecs.component.Vec2.init(3, 2) },
        ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/kattis.png") },
    });

    // for (5..15) |i| {
    //     for (5..15) |j| {
    //         const x = rand.int(i4);
    //         const xx = if (x == 0) 1 else x;
    //         const y = rand.int(i4);
    //         const yy = if (y == 0) 1 else y;

    //         _ = try sim.world.spawnWith(.{
    //             ecs.component.Pos{ .pos = [_]i32{ @intCast(i * 16), @intCast(j * 16) } },
    //             ecs.component.Col{ .dim = [_]i32{ 16, 16 } },
    //             ecs.component.Mov{ .velocity = ecs.component.Vec2.init(xx, yy) },
    //             ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/kattis.png") },
    //         });
    //     }
    // }

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
    if (rl.isKeyDown(rl.KeyboardKey.key_r)) {
        for (entities, 0..) |e, i| {
            const pos = try sim.world.inspect(e, ecs.component.Pos);
            switch (i) {
                0 => pos.pos = [_]i32{ 16 * 1, 16 * 3 },
                1 => pos.pos = [_]i32{ 16 * 1, 16 * 4 },
                2 => pos.pos = [_]i32{ 16 * 2, 16 * 3 },
                else => {},
            }
        }
    }
    collide.movementSystem(&sim.world, &collisions) catch @panic("movement system failed");
    // for (collisions.collisions.keys()) |c| {
    //     const x = rand.int(i4);
    //     const xx = if (x == 0) 1 else x;
    //     const y = rand.int(i4);
    //     const yy = if (y == 0) 1 else y;

    //     const mov = try sim.world.inspect(c.a, ecs.component.Mov);
    //     mov.velocity.set([_]i4{ xx, yy });
    // }
    collisions.clear();
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
                @intCast(2 * state.horizontal()),
                @intCast(3 * state.vertical()),
            });
        }
    }
}
