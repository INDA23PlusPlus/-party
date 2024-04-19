const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const render = @import("../render.zig");
const AssetManager = @import("../AssetManager.zig");
const input = @import("../input.zig");
const constants = @import("../constants.zig");
const animations = @import("animations.zig");

pub fn update(world: *ecs.world.World) void {
    var query = world.query(&.{ ecs.component.Tex, ecs.component.Anm }, &.{});
    while (query.next()) |_| {
        const tex_component = query.get(ecs.component.Tex) catch unreachable;
        const anm_component = query.get(ecs.component.Anm) catch unreachable;

        const frames = animations.data(anm_component.animation);
        const subframe_max = @as(u32, @truncate(frames.len)) * anm_component.interval;

        if (anm_component.subframe >= subframe_max) {
            if (anm_component.looping) {
                anm_component.subframe = 0;
            } else {
                anm_component.subframe = subframe_max - 1;
            }
        }

        const frame_index = anm_component.subframe / anm_component.interval;

        tex_component.u = frames[frame_index].u;
        tex_component.v = frames[frame_index].v;
        anm_component.subframe += 1;
    }
}
