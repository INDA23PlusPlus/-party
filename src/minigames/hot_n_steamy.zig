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
//
const gravity = ecs.component.Vec2.init(0, ecs.component.F32.init(1, 10));
const boost = ecs.component.Vec2.init(0, ecs.component.F32.init(-1, 4));

pub fn init(sim: *simulation.Simulation) !void {
    for (0..constants.max_player_count) |id| {
        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = id }, ecs.component.Pos{ .pos = .{ 8, 0 } }, ecs.component.Mov{ .acceleration = gravity },
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/kattis.png"),
                .tint = constants.player_colors[id],
            },
            ecs.component.Anm{ .animation = Animation.KattisRun, .interval = 16, .looping = true },
        });
    }
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState, arena: std.mem.Allocator) !void {
    var collisions = collision.CollisionQueue.init(arena) catch @panic("could not initialize collision queue");

    // try gravitySystem(&sim.world);
    try jetpackSystem(&sim.world, inputs);
    movement.update(&sim.world, &collisions, arena) catch @panic("movement system failed");
    try deathSystem(&sim.world);
    animator.update(&sim.world);
}

fn gravitySystem(world: *ecs.world.World) !void {
    var query = world.query(&.{ecs.component.Mov}, &.{});
    while (query.next()) |_| {
        const mov = try query.get(ecs.component.Mov);
        mov.acceleration = mov.acceleration.add(gravity);
    }
}

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

fn deathSystem(world: *ecs.world.World) !void {
    var query = world.query(&.{ecs.component.Pos}, &.{});
    while (query.next()) |entity| {
        const pos = try query.get(ecs.component.Pos);
        const y = pos.pos[1];
        if (y > constants.world_height + 16 or y < 0 - 16) {
            world.kill(entity);
            std.debug.print("entity {} died\n", .{entity.identifier});
        }
    }
}
