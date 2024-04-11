const simulation = @import("../simulation.zig");
const input_state = @import("../input.zig");

/// Interface for a mini-game look at games/example.zig for a reference implementation:
pub const Minigame = struct {
    init: *const fn (simulation: *simulation.Simulation) simulation.SimulationError!void,

    // TODO: pass in collisions
    update: *const fn (world: *simulation.Simulation, input: *const input_state.InputState) simulation.SimulationError!void,
};
