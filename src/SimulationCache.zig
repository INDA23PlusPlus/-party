/// This struct keeps a copy of simulation states
/// at different elapsed ticks. This is done so
/// that re-simulation doesn't require one to start
/// from tick 0 each time.
const std = @import("std");
const simulation = @import("./simulation.zig");
const input = @import("./input.zig");

const Invariables = @import("./Invariables.zig");

start_state: simulation.Simulation = .{},
round_buffer: [128]simulation.Simulation = undefined,
head_tick_elapsed: u64 = std.math.maxInt(u64),

const Self = @This();

pub inline fn latest(self: *Self) *simulation.Simulation {
    return &self.round_buffer[self.head_tick_elapsed % self.round_buffer.len];
}

inline fn skip_tick(self: *Self) *simulation.Simulation {
    const from = self.latest();
    self.head_tick_elapsed += 1;
    const to = self.latest();
    to.* = from.*;
    return to;
}

pub fn simulate(self: *Self, input_state: input.Timeline, rt: Invariables) !void {
    const to = self.skip_tick();
    try simulation.simulate(to, input_state, rt);
}

pub fn reset(self: *Self) void {
    self.head_tick_elapsed = 0;
    self.round_buffer[0] = self.start_state;
}

pub fn rewind(self: *Self, tick: u64) void {
    if (tick == 0) {
        self.reset();
        return;
    }
    if (tick > self.head_tick_elapsed) {
        // We ignore requests to rewind into the future.
        return;
    }
    if (self.head_tick_elapsed - tick >= self.round_buffer.len) {
        self.reset();
        std.debug.print("rewinding too far caused the simulation to reset", .{});
        return;
    }
    self.head_tick_elapsed = tick;
    std.debug.assert(self.latest().meta.ticks_elapsed == tick);
}
