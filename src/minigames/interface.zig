const Allocator = @import("std").mem.Allocator;

const simulation = @import("../simulation.zig");
const input_state = @import("../input.zig");

/// Interface for a mini-game look at games/example.zig for a reference implementation:
pub const Minigame = struct {
    /// The name of the minigame.
    name: []const u8,

    /// Initializes the minigame.
    /// This should include setting up the starting positions of the players and the play area.
    init: *const fn (
        sim: *simulation.Simulation,
        input: *const input_state.InputState,
    ) simulation.SimulationError!void,

    /// Updates the minigame one frame.
    /// Memory allocations using `arena` are nonpersistent and automatically freed after each frame.
    update: *const fn (
        sim: *simulation.Simulation,
        input: *const input_state.InputState,
        arena: Allocator,
    ) simulation.SimulationError!void,
};
