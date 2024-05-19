const std = @import("std");
const input = @import("input.zig");

pub const Packet = struct { tick: u64, data: input.AllPlayerButtons, players: input.PlayerBitSet };
const max_backlog = 1024;

rw_lock: std.Thread.RwLock = .{},

incoming_data: [max_backlog]Packet = undefined,
incoming_data_count: u64 = 0,

outgoing_data: [max_backlog]Packet = undefined,
outgoing_data_count: u64 = 0,

client_acknowledge_tick: u64 = 0,
// A high value prevents the client from acting before it has even 
// had the chance to receive some inptuts from the server.
server_timeline_length: u64 = std.math.maxInt(u64), 

const Self = @This();

pub fn interchange(self: *Self, other: *Self) void {
    self.rw_lock.lock();
    other.rw_lock.lock();

    //std.debug.print("attempt interchange: {d} {d}\n", .{self.outgoing_data_len, other.incoming_data_count});
    while (self.outgoing_data_count > 0 and other.incoming_data_count < max_backlog) {
        const new_outgoing_len = self.outgoing_data_count - 1;
        self.outgoing_data_count = new_outgoing_len;
        other.incoming_data[other.incoming_data_count] = self.outgoing_data[new_outgoing_len];
        other.incoming_data_count += 1;
    }

    while (self.incoming_data_count < max_backlog and other.outgoing_data_count > 0) {
        const new_outgoing_len = other.outgoing_data_count - 1;
        other.outgoing_data_count = new_outgoing_len;
        self.incoming_data[self.incoming_data_count] = other.outgoing_data[new_outgoing_len];
        self.incoming_data_count += 1;
    }

    // Transfer some constants. This operation is not symmetric.
    // Results will vary between a.interchange(b) and b.interchange(a).
    // TODO: for this reason, a better name for the procedure should be found.
    other.client_acknowledge_tick = self.client_acknowledge_tick;
    self.server_timeline_length = other.server_timeline_length;

    self.rw_lock.unlock();
    other.rw_lock.unlock();
}
