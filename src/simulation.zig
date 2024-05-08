const ecs = @import("ecs/ecs.zig");
const constants = @import("constants.zig");
const std = @import("std");
const input = @import("input.zig");
const Invariables = @import("Invariables.zig");

const seed = 555;

/// Data that is kept between minigames (such as seed, scores, etc)
pub const Metadata = struct {
    global_score: [constants.max_player_count]u32 = [_]u32{0} ** constants.max_player_count,
    ticks_elapsed: u64 = 1,

    minigame_id: usize = 0,
    minigame_prng: std.rand.DefaultPrng = std.rand.DefaultPrng.init(seed),
    minigame_placements: [constants.max_player_count]u32 = [_]u32{0} ** constants.max_player_count,
    minigame_timer: u32 = 0,
    minigame_counter: u32 = 0,
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
pub fn start(sim: *Simulation, rt: Invariables) !void {
    try rt.minigames_list[sim.meta.minigame_id].init(sim, .{
        .buttons = &.{},
    });
}

/// Simulate one tick in the game world.
/// All generic game code will be called from this function and should not
/// use anything outside of the world or the input frame. Failing to do so
/// will lead to inconsistencies.
pub fn simulate(sim: *Simulation, input_state: input.Timeline, rt: Invariables) !void {
    const frame_start_minigame = sim.meta.minigame_id;

    sim.meta.ticks_elapsed += 1;

    try rt.minigames_list[sim.meta.minigame_id].update(sim, input_state, rt);

    // Handles transitions between minigames.
    if (frame_start_minigame != sim.meta.minigame_id) {
        sim.world.reset();
        sim.meta.minigame_timer = 0;
        sim.meta.minigame_counter = 0;
        sim.meta.minigame_prng.seed(seed + sim.meta.ticks_elapsed);
        try rt.minigames_list[sim.meta.minigame_id].init(sim, input_state);
    }
}
