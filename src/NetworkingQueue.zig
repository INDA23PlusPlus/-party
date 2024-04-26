const std = @import("std");
const input = @import("input.zig");

const StampedInput = struct { tick: u64, player: u32, data: input.InputState };
const max_backlog = 1024;

rw_lock: std.Thread.RwLock = .{},

incoming_data: [max_backlog]StampedInput = undefined,
incoming_data_len: u64 = 0,

outgoing_data: [max_backlog]StampedInput = undefined,
outgoing_data_len: u64 = 0,

const Self = @This();

pub fn interchange(self: *Self, other: *Self) void {
    self.rw_lock.lock();
    other.rw_lock.lock();

    while (self.outgoing_data_len > 0 and other.incoming_data.len < max_backlog) {
        const new_outgoing_len = self.outgoing_data_len - 1;
        self.outgoing_data_len = new_outgoing_len;
        other.incoming_data[other.incoming_data_len] = self.outgoing_data[new_outgoing_len];
        other.incoming_data_len += 1;
    }

    while (self.incoming_data_len < max_backlog and other.outgoing_data_len > 0) {
        const new_outgoing_len = other.outgoing_data_len - 1;
        other.outgoing_data_len = new_outgoing_len;
        self.incoming_data[self.incoming_data_len] = other.outgoing_data[new_outgoing_len];
        self.incoming_data_len += 1;
    }

    self.rw_lock.unlock();
    other.rw_lock.unlock();
}
