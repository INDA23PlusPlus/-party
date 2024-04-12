const std = @import("std");
const rl = @import("raylib");
const simulation = @import("../simulation.zig");
const input = @import("../input.zig");

pub fn init(sim: *simulation.Simulation) !void {
    _ = sim;
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState) !void {
    rl.drawText("This is a new minigame", 64, 8, 32, rl.Color.blue);
    _ = inputs;
    _ = sim;
}
