const ecs = @import("ecs/ecs.zig");
const constants = @import("constants.zig");
const std = @import("std");
const input = @import("input.zig");
const Invariables = @import("Invariables.zig");

/// Data that is kept between minigames (such as seed, scores, etc)
pub const Metadata = struct {
    score: [constants.max_player_count]u32 = [_]u32{0} ** constants.max_player_count,
    seed: usize = 555,
    ticks_elapsed: usize = 0,
    minigame_id: usize = 0,
    minigame_ticks_per_update: u32 = 1, // Used by minigames to
};

pub const Simulation = struct {
    world: ecs.world.World = .{},
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
pub const SimulationError = ecs.world.WorldError;

/// Should this be here?
pub fn init(sim: *Simulation, rt: Invariables) !void {
    sim.meta.minigame_ticks_per_update = 1;
    try rt.minigames_list[sim.meta.minigame_id].init(sim, &.{input.default_input_state});
}

/// Simulate one tick in the game world.
/// All generic game code will be called from this function and should not
/// use anything outside of the world or the input frame. Failing to do so
/// will lead to inconsistencies.
pub fn simulate(sim: *Simulation, input_state: []const input.InputState, rt: Invariables) !void {
    const frame_start_minigame = sim.meta.minigame_id;

    sim.meta.ticks_elapsed += 1;

    // Handles transitions between minigames.
    try rt.minigames_list[sim.meta.minigame_id].update(sim, input_state, rt);

    // TODO: game selection
    // We could select the game randomly by first switching to a "game select minigame" with ID 0 maybe?

    if (frame_start_minigame != sim.meta.minigame_id) {
        sim.world.reset();
        sim.meta.minigame_ticks_per_update = 1;
        try rt.minigames_list[sim.meta.minigame_id].init(sim, input_state);
    }
}
