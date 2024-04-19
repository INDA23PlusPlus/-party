const rl = @import("raylib");
const std = @import("std");
const ecs = @import("ecs/ecs.zig");
const constants = @import("constants.zig");

// This is the system for the 'Tmr' component
// Not to be confused with frame time or ticks

pub fn update(world: *ecs.world.World) void {
    var query = world.query(&.{ecs.component.Tmr}, &.{});
    while (query.next()) |entity| {
        const tmr = query.get(ecs.component.Tmr) catch unreachable;
        if (tmr.fired) {
            if (tmr.repeat) {
                tmr.fired = false;
                tmr.elapsed = 0;
            }
        } else {
            if (tmr.elapsed >= tmr.delay) {
                tmr.action(world, entity);
                tmr.fired = true;
            }
            tmr.elapsed += 1;
        }
    }
}
