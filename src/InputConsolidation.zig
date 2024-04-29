const std = @import("std");
const input = @import("input.zig");
const constants = @import("constants.zig");
const Controller = @import("Controller.zig");
const Self = @This();

const InputStateArrayList = std.ArrayListUnmanaged(input.AllPlayerButtons);
const IsLocalBitSet = std.bit_set.IntegerBitSet(constants.max_player_count);
const LocalArrayList = std.ArrayListUnmanaged(IsLocalBitSet);

rw_lock: std.Thread.RwLock = .{},

buttons: InputStateArrayList,
local: LocalArrayList,

newest_remote_frame: u64 = 0,
frames_sent: u64 = 0,

pub fn init(allocator: std.mem.Allocator) !Self {
    var buttons = try InputStateArrayList.initCapacity(allocator, 1024);
    try buttons.append(allocator, input.default_input_state);
    var local = try LocalArrayList.initCapacity(allocator, 1024);
    try local.append(allocator, IsLocalBitSet.initEmpty());
    return .{
        .buttons = buttons,
        .local = local,
    };
}

fn extendTimeline(self: *Self, allocator: std.mem.Allocator, tick: u64) !void {
    const guess_buttons = self.buttons.getLast();
    const guess_local = self.local.getLast();
    const start = self.buttons.items.len;
    try self.buttons.ensureTotalCapacity(allocator, tick + 1);
    try self.local.ensureTotalCapacity(allocator, tick + 1);
    self.buttons.items.len = tick + 1;
    self.local.items.len = tick + 1;
    for (self.buttons.items[start..]) |*frame| {
        frame.* = guess_buttons;
    }
    for (self.local.items[start..]) |*frame| {
        frame.* = guess_local;
    }
}

pub fn localUpdate(self: *Self, allocator: std.mem.Allocator, controllers: []Controller, tick: u64) !input.Timeline {
    if (tick >= self.newest_remote_frame) {
        try self.extendTimeline(allocator, tick);
        self.buttons.items[tick] = Controller.poll(controllers, self.buttons.items[tick - 1]);
        // TODO: fill out self.local too.
    }
    return .{
        .buttons = self.buttons.items[0..tick],
    };
}

pub fn remoteUpdate(self: *Self, allocator: std.mem.Allocator, new_state: input.InputState, tick: usize) !input.Timeline {
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
    return .{
        .buttons = self.buttons.items[0..tick],
    };
}
