const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const render = @import("../render.zig");
const AssetManager = @import("../AssetManager.zig");
const input = @import("../input.zig");
const collide = @import("../physics/collide.zig");

var collisions: collide.CollisionQueue = undefined;

pub fn init(sim: *simulation.Simulation) !void {
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{},
        ecs.component.Mov{},
        ecs.component.Col{ .dim = @Vector(2, i32){ 20, 20 } },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/kattis.png"),
            .tint = rl.Color.white,
        },
        ecs.component.Plr{ .id = 0 },
    });
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = @Vector(2, i32){ 64, 64 } },
        ecs.component.Mov{},
        ecs.component.Col{ .dim = @Vector(2, i32){ 20, 20 } },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/kattis.png"),
            .tint = rl.Color.red,
        },
        ecs.component.Plr{ .id = 1 },
    });

    collisions = collide.CollisionQueue.init(std.heap.page_allocator);
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState) !void {
    try inputSystem(&sim.world, inputs);
    collide.movementSystem(&sim.world, &collisions) catch @panic("movement system failed");
}

fn inputSystem(world: *ecs.world.World, inputs: *const input.InputState) !void {
    var query = world.query(&.{ ecs.component.Mov, ecs.component.Plr }, &.{});
    while (query.next()) |_| {
        const mov = query.get(ecs.component.Mov) catch unreachable;
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const state = inputs[plr.id];
        if (state.is_connected) {
            mov.velocity.set(@Vector(2, i16){
                @intCast(5 * state.horizontal()),
                @intCast(5 * state.vertical()),
            });
        }
    }
}
