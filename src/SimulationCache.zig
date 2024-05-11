/// This struct keeps a copy of simulation states
/// at different elapsed ticks. This is done so
/// that re-simulation doesn't require one to start
/// from tick 0 each time.
const std = @import("std");
const simulation = @import("./simulation.zig");
const input = @import("./input.zig");

const Invariables = @import("./Invariables.zig");

round_buffer: [20]simulation.Simulation = [_]simulation.Simulation{.{}} ** 20,
head_tick_elapsed: u64 = 0,

const Self = @This();

pub inline fn latest(self: *Self) *simulation.Simulation {
    return &self.round_buffer[self.head_tick_elapsed % self.round_buffer.len];
}

pub inline fn skip_tick(self: *Self) *simulation.Simulation {
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

pub fn rewind(self: *Self, tick: u64) void {
    std.debug.assert(tick > 0);
    std.debug.assert(tick < self.head_tick_elapsed);
    if (self.head_tick_elapsed - tick >= self.round_buffer.len) {
        std.debug.panic("tried to rewind too far", .{});
    }
    self.head_tick_elapsed = tick;
}
