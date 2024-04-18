const std = @import("std");
const simulation = @import("../simulation.zig");
const input = @import("../input.zig");

const Allocator = std.mem.Allocator;

pub fn init(sim: *simulation.Simulation, inputs: *const input.InputState) simulation.SimulationError!void {
    _ = sim;
    _ = inputs;
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState, arena: Allocator) simulation.SimulationError!void {
    _ = sim;
    _ = inputs;
    _ = arena;
}
