/// Interface for a mini-game look at games/example.zig for a reference implementation:

const Allocator = @import("std").mem.Allocator;
const simulation = @import("../simulation.zig");
const input_state = @import("../input.zig");
const Invariables = @import("../Invariables.zig");

/// The name of the minigame.
name: [:0]const u8,

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
    rt: Invariables,
) simulation.SimulationError!void,

// TODO: With the amount of rl.drawText in update() we should probably introduce a render()
// Alternatively, refactor all update() such that text is rendered using the ECS perhaps. Up for discussion.
