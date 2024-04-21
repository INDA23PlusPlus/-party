const rl = @import("raylib");
const std = @import("std");
const ecs = @import("ecs/ecs.zig");
const constants = @import("constants.zig");

// DEPRACTATED

// Use `ecs.component.Ctr` instead for timers and regular systems for callbacks.
// `update()` has been temporarily updated to not use callbacks.

// This is the system for the 'TimerDepracated' component
// Not to be confused with frame time or ticks

pub fn update(world: *ecs.world.World) void {
    var query = world.query(&.{ecs.component.TimerDepracated}, &.{});
    while (query.next()) |entity| {
        const tmr = query.get(ecs.component.TimerDepracated) catch unreachable;
        if (tmr.fired) {
            if (tmr.repeat) {
                tmr.fired = false;
                tmr.elapsed = 0;
            }
        } else {
            if (tmr.elapsed >= tmr.delay) {
                action(tmr.action, world, entity);
                tmr.fired = true;
            }
            tmr.elapsed += 1;
        }
    }
}

pub const Action = enum {
    default,
    killEntity,
    hnsSpawnRandomObstacle,
};

fn action(id: Action, world: *ecs.world.World, entity: ecs.entity.Entity) void {
    switch (id) {
        .default => {},
        .killEntity => world.kill(entity),
        .hnsSpawnRandomObstacle => @import("minigames/hot_n_steamy.zig").spawnRandomObstacle(world, entity),
    }
}
