const ecs = @import("ecs/world.zig");
const constants = @import("constants.zig");
const std = @import("std");
const minigame = @import("minigames/interface.zig");

/// Data that is kept between minigames (such as seed, scores, etc)
pub const Metadata = struct {
    score: [constants.max_player_count]u32 = [_]u32{0} ** constants.max_player_count,
    seed: usize = 555,
    ticks_elapsed: usize = 0,
    minigame_id: usize = 0,
};

pub const Simulation = struct {
    world: ecs.World,
    meta: Metadata = .{},
};

/// A Simulation paired together with an rw_lock used
/// to coordinate two (or more) threads accessing the same Simulation.
/// OBS: This does not automatically make procedures inside
/// of World thread-safe. The rw_lock must be properly used first.
pub const SharedSimulation = struct {
    sim: Simulation,
    rw_lock: std.Thread.RwLock,
};

/// All the errors that may happen during simulation.
pub const SimulationError = ecs.WorldError;

/// Simulate one tick in the game world.
/// All generic game code will be called from this function and should not
/// use anything outside of the world or the input frame. Failing to do so
/// will lead to inconsistencies.
pub fn simulate(minigames_list: []const minigame.Minigame, sim: *Simulation) !void {
    const frame_start_minigame = sim.meta.minigame_id;

    // TODO: Add input as an argument.

    var pos_query = sim.world.query(&.{ecs.Position}, &.{});
    while (pos_query.next()) |_| {
        const pos = try pos_query.get(ecs.Position);
        pos.x += 1;
        pos.y += 1;
    }

    // Handles transitions between minigames.
    try minigames_list[sim.meta.minigame_id].update(sim);

    // TODO: game selection
    // We could select the game randomly by first switching to a "game select minigame" with ID 0 maybe?

    if (frame_start_minigame != sim.meta.minigame_id) {
        // TODO: Clear the world?
        try minigames_list[sim.meta.minigame_id].init(sim);
    }

}
