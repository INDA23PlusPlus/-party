const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const render = @import("../render.zig");
const AssetManager = @import("../AssetManager.zig");
const Animation = @import("../animation/animations.zig").Animation;
const Invariables = @import("../Invariables.zig");
const input = @import("../input.zig");
const animator = @import("../animation/animator.zig");
const collision = @import("../physics/collision.zig");
const movement = @import("../physics/movement.zig");

pub fn init(sim: *simulation.Simulation, _: []const input.InputState) !void {
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{},
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/kattis.png"),
            .tint = rl.Color.white,
        },
        ecs.component.Mov{},
        ecs.component.Col{
            .dim = [_]i32{ 16, 16 },
            .layer = collision.Layer{ .base = false, .player = true },
            .mask = collision.Layer{ .base = false, .player = false }, // This player cannot collide with other players.
        },
        ecs.component.Plr{ .id = 0 },
        ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
    });
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = @Vector(2, i32){ 16, 0 } },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/kattis.png"),
            .tint = rl.Color.red,
        },
        ecs.component.Mov{},
        ecs.component.Col{
            .dim = [_]i32{ 16, 16 },
            .layer = collision.Layer{ .base = false, .player = true },
            .mask = collision.Layer{ .base = false, .player = false }, // This player cannot collide with other players.
        },
        ecs.component.Plr{ .id = 1 },
        ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
    });
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = @Vector(2, i32){ 32, 0 } },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/kattis.png"),
            .tint = rl.Color.blue,
        },
        ecs.component.Mov{},
        ecs.component.Col{
            .dim = [_]i32{ 16, 16 },
            .layer = collision.Layer{ .base = false, .player = false },
            .mask = collision.Layer{ .base = false, .player = true }, // This entity can collide with other players.
        },
        ecs.component.Plr{ .id = 2 },
        ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
    });
}

pub fn update(sim: *simulation.Simulation, inputs_timeline: []const input.InputState, rt: Invariables) !void {
    const inputs = &inputs_timeline[inputs_timeline.len - 1];
    var collisions = collision.CollisionQueue.init(rt.arena) catch @panic("collision");

    try inputSystem(&sim.world, inputs);
    movement.update(&sim.world, &collisions, rt.arena) catch @panic("movement");

    animator.update(&sim.world); // I don't think this should be here

    // Draw debug text (should not be here)
    rl.drawText("++party :3", 64, 8, 32, rl.Color.blue);
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
                @intCast(3 * state.vertical_inv()),
            });

            const anm = try query.get(ecs.component.Anm);
            if (state.direction() == input.InputDirection.None) {
                anm.animation = Animation.KattisIdle;
                anm.interval = 16;
            } else {
                anm.animation = Animation.KattisRun;
                anm.interval = 8;
            }
        }
    }
}
