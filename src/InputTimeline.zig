const std = @import("std");
const input = @import("input.zig");
const Controller = @import("controller.zig");
const Self = @This();

timeline_index: usize = 0,
rw_lock: std.Thread.RwLock = .{},
recent_timeline: [40]input.InputState = [_]input.InputState{input.DefaultInputState} ** 40,

pub fn localUpdate(self: *Self, controllers: []Controller, tick: usize) *input.InputState {
    const state = &self.recent_timeline[tick % self.recent_timeline.len];
    Controller.poll(controllers, state, tick);
    return state;
}

pub fn remoteUpdate(tick: usize) void {
    _ = tick;
}


