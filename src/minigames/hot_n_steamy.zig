const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const render = @import("../render.zig");
const AssetManager = @import("../AssetManager.zig");
const input = @import("../input.zig");
const Animation = @import("../animation/animations.zig").Animation;
const animator = @import("../animation/animator.zig");
const constants = @import("../constants.zig");
const movement = @import("../physics/movement.zig");
const collision = @import("../physics/collision.zig");

// TODO: Spawn and collide with obstacles
//Global Constants
const gravity = ecs.component.Vec2.init(0, ecs.component.F32.init(1, 10));
const boost = ecs.component.Vec2.init(0, ecs.component.F32.init(-1, 4));
var object_acc = ecs.component.Vec2.init(-4, 0);
var prng = std.rand.DefaultPrng.init(555);
const rand = prng.random();
const baseObHeight = 7;

pub fn init(sim: *simulation.Simulation) !void {
    for (0..constants.max_player_count) |id| {
        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = id }, ecs.component.Pos{ .pos = .{ 8, 0 } },
            ecs.component.Mov{
                .acceleration = gravity,
            },
            ecs.component.Col{
                .dim = .{ 16, 16 },
                .layer = collision.Layer{ .base = false, .player = true },
                .mask = collision.Layer{ .base = false, .player = false },
            },
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/kattis.png"),
                .tint = constants.player_colors[id],
            },
            ecs.component.Anm{ .animation = Animation.KattisRun, .interval = 16, .looping = true },
        });
        // _ = try sim.world.spawnWith(.{
        //     ecs.component.Pos{ .pos = .{ 0, constants.world_height - 16 } },
        //     ecs.component.Col{
        //         .dim = [_]i32{ 16, 16 * 18 },
        //         .layer = collision.Layer{ .base = false, .player = false },
        //         .mask = collision.Layer{ .base = false, .player = true },
        //     },
        // });
    }
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState, arena: std.mem.Allocator) !void {
    var collisions = collision.CollisionQueue.init(arena) catch @panic("could not initialize collision queue");

    // try gravitySystem(&sim.world);
    try jetpackSystem(&sim.world, inputs);
    movement.update(&sim.world, &collisions, arena) catch @panic("movement system failed");

    if (sim.meta.ticks_elapsed % (80 - (sim.meta.ticks_elapsed / 80)) == 0) {
        try obsticleGenerator(&sim.world, std.Random.intRangeAtMost(rand, i32, -6, 6));
    }
    sim.meta.ticks_elapsed += 1;
    try deathSystem(&sim.world);
    animator.update(&sim.world);
}

// fn gravitySystem(world: *ecs.world.World) !void {
//     var query = world.query(&.{ecs.component.Mov}, &.{});
//     while (query.next()) |_| {
//         const mov = try query.get(ecs.component.Mov);
//         mov.acceleration = mov.acceleration.add(gravity);
//     }
// }

fn jetpackSystem(world: *ecs.world.World, inputs: *const input.InputState) !void {
    var query = world.query(&.{ ecs.component.Mov, ecs.component.Plr }, &.{});
    while (query.next()) |_| {
        const plr = try query.get(ecs.component.Plr);
        const mov = try query.get(ecs.component.Mov);
        const state = inputs[plr.id];
        if (state.is_connected) {
            if (state.up.is_down) {
                mov.velocity = mov.velocity.add(boost);
            }
        }
    }
}

fn obsticleGenerator(world: *ecs.world.World, length: i32) !void {
    _ = try world.spawnWith(.{
        ecs.component.Pos{ .pos = [_]i32{ constants.world_width, 0 } },
        ecs.component.Col{
            .dim = [_]i32{ 16, 16 * (baseObHeight - length) },
            .layer = collision.Layer{ .base = false, .player = false },
            .mask = collision.Layer{ .base = false, .player = true },
        },
        ecs.component.Mov{ .velocity = object_acc },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/test.png"),
            .tiles_x = 1,
            .tiles_y = @as(usize, @intCast(baseObHeight - length)),
        },
    });
    _ = try world.spawnWith(.{
        ecs.component.Pos{ .pos = [_]i32{ constants.world_width, constants.world_height - 16 * (baseObHeight + length) } },
        ecs.component.Col{
            .dim = [_]i32{ 16, 16 * (baseObHeight + length) },
            .layer = collision.Layer{ .base = false, .player = false },
            .mask = collision.Layer{ .base = false, .player = true },
        },
        ecs.component.Mov{ .velocity = object_acc },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/test.png"),
            .tiles_x = 1,
            .tiles_y = @as(usize, @intCast(baseObHeight + length)),
        },
    });
}

fn deathSystem(world: *ecs.world.World) !void {
    var query = world.query(&.{ecs.component.Pos}, &.{});
    while (query.next()) |entity| {
        const pos = try query.get(ecs.component.Pos);
        const y = pos.pos[1];
        const x = pos.pos[0];
        if (y > constants.world_height + 16 or y < 0 - 16 or x < 0 - 16) {
            world.kill(entity);
            std.debug.print("entity {} died\n", .{entity.identifier});
        }
    }
}
