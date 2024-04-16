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
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState) !void {
    var query = sim.world.query(&.{ ecs.component.Pos, ecs.component.Plr, ecs.component.Anm }, &.{});

    while (query.next()) |_| {
        const pos = try query.get(ecs.component.Pos);
        const plr = try query.get(ecs.component.Plr);
        const state = inputs[plr.id];
        if (state.is_connected) {
            pos.pos[1] += 15 * state.vertical();
            pos.pos[1] += 5;
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
}
