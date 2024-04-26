const std = @import("std");
const input = @import("input.zig");
const Controller = @import("controller.zig");
const Self = @This();

const InputStateArrayList = std.ArrayListUnmanaged(input.InputState);

rw_lock: std.Thread.RwLock,
timeline: InputStateArrayList,
newest_remote_frame: u64,

pub fn init(allocator: std.mem.Allocator) !Self {
    var timeline = try InputStateArrayList.initCapacity(allocator, 1024);
    try timeline.append(allocator, input.default_input_state);
    return .{
        .rw_lock = .{},
        .newest_remote_frame = 0,
        .timeline = timeline,
    };
}

fn extendTimeline(self: *Self, allocator: std.mem.Allocator, tick: u64) !void {
    const start_frame = self.timeline.getLast();
    const start = self.timeline.items.len;
    try self.timeline.ensureTotalCapacity(allocator, tick + 1);
    self.timeline.items.len = tick + 1;
    for (self.timeline.items[start..]) |*frame| {
        frame.* = start_frame;
    }
}

pub fn localUpdate(self: *Self, allocator: std.mem.Allocator, controllers: []Controller, tick: u64) ![]input.InputState {
    if (tick >= self.newest_remote_frame) {
        try self.extendTimeline(allocator, tick);
        Controller.poll(controllers, &self.timeline.items[tick], tick);
    }
    return self.timeline.items[0..tick];
}

pub fn remoteUpdate(self: *Self, allocator: std.mem.Allocator, new_state: input.InputState, tick: usize) ![]input.InputState {
    if (tick < self.newest_remote_frame) {
        @panic("the inputs came out of order");
    }
    try self.extendTimeline(allocator, allocator, tick);
    for (self.timeline.items[tick..]) |*frame| {
        for (frame, 0..) |*player, index| {
            if (player.is_local) {
                continue;
            }
            player = new_state[index];
        }
    }
    self.newest_remote_frame = tick;
    return self.timelie.items[0..tick];
}
