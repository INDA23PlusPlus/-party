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

pub fn init(sim: *simulation.Simulation) !void {
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{},
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/kattis.png"),
            .tint = rl.Color.white,
        },
        ecs.component.Plr{ .id = 0 },
        ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
    });
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = @Vector(2, i32){ 32, 64 } },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/kattis.png"),
            .tint = rl.Color.red,
        },
        ecs.component.Plr{ .id = 1 },
        ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
    });
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState) !void {
    // TODO: Possible pass in a frame_allocator.

    // Move all player controllers
    var query = sim.world.query(&.{ ecs.component.Pos, ecs.component.Plr, ecs.component.Anm }, &.{});
    while (query.next()) |_| {
        const pos = try query.get(ecs.component.Pos);
        const plr = try query.get(ecs.component.Plr);
        const state = inputs[plr.id];
        if (state.is_connected) {
            pos.pos[0] += 5 * state.horizontal();
            pos.pos[1] += 5 * state.vertical();
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
