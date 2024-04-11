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

//var frame_arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//var frame_allocator: *std.mem.Allocator = &frame_arena.allocator();

pub fn init(sim: *simulation.Simulation) !void {
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .vec = .{ 0, 0 } },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/kattis.png"),
            .tint = rl.Color.white,
        },
        ecs.component.Ctl{ .id = 0 },
        ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
    });
}

const win: bool = false;

pub fn update(sim: *simulation.Simulation) !void {
    // example of using a frame allocator
    //defer _ = frame_arena.reset(std.heap.ArenaAllocator.ResetMode.retain_capacity);

    // Move all player controllers
    var query = sim.world.query(&.{ ecs.component.Pos, ecs.component.Ctl, ecs.component.Anm }, &.{});
    while (query.next()) |_| {
        const pos = try query.get(ecs.component.Pos);
        const ctl = try query.get(ecs.component.Ctl);
        const state = input.get(ctl.id);
        if (state.isConnected) {
            pos.vec[0] += 5 * state.horizontal();
            pos.vec[1] += 5 * state.vertical();
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

    animator.update(&sim.world); // I don't think this should be here

    // Draw debug text (should not be here)
    rl.drawText("++party :3", 64, 8, 32, rl.Color.blue);
}
