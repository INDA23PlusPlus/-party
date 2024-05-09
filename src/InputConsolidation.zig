const std = @import("std");
const input = @import("input.zig");
const constants = @import("constants.zig");
const Controller = @import("Controller.zig");
const Self = @This();

const InputStateArrayList = std.ArrayListUnmanaged(input.AllPlayerButtons);
const PlayerBitSet = std.bit_set.IntegerBitSet(constants.max_player_count);
const PlayerBitSetArrayList = std.ArrayListUnmanaged(PlayerBitSet);
const empty_player_bit_set = PlayerBitSet.initEmpty();

rw_lock: std.Thread.RwLock = .{},
buttons: InputStateArrayList,
is_certain: PlayerBitSetArrayList,
//received: PlayerBitSetArrayList,


// TODO: Remove
newest_remote_frame: u64 = 0,


pub fn init(allocator: std.mem.Allocator) !Self {
    // We append one to each array because extendTimeline() must have at least one frame available
    // such that it can be used as inspiration for the rest of the timeline.
    var buttons = try InputStateArrayList.initCapacity(allocator, 1024);
    try buttons.append(allocator, input.default_input_state);
    var is_certain = try PlayerBitSetArrayList.initCapacity(allocator, 1024);
    try is_certain.append(allocator, empty_player_bit_set);
    //var received = try PlayerBitSetArrayList.initCapacity(allocator, 1024);
    //try received.append(allocator, PlayerBitSet.initEmpty());
    return .{
        .buttons = buttons,
        .is_certain = is_certain,
        //.received = received,
    };
}

fn extendTimeline(self: *Self, allocator: std.mem.Allocator, tick: u64) !void {
    if (tick + 1 < self.buttons.items.len) {
        // No need to extend the timeline.
        return;
    }

    const guess_buttons = self.buttons.getLast();
    const start = self.buttons.items.len - 1;

    try self.buttons.ensureTotalCapacity(allocator, tick + 1);
    self.buttons.items.len = tick + 1;
    try self.is_certain.ensureTotalCapacity(allocator, tick + 1);
    self.is_certain.items.len = tick + 1;

    for (self.buttons.items[start..]) |*frame| {
        frame.* = guess_buttons;
    }

    for (self.is_certain.items[start..]) |*frame| {
        frame.* = empty_player_bit_set;
    }
}

pub fn localUpdate(self: *Self, allocator: std.mem.Allocator, controllers: []Controller, tick: u64) !void {
    if (tick >= self.newest_remote_frame) {
        try self.extendTimeline(allocator, tick);
        self.buttons.items[tick] = Controller.poll(controllers, self.buttons.items[tick - 1]);
        var is_local = input.IsLocalBitfield.initEmpty();
        for (controllers) |controller| {
            if (controller.is_assigned()) {
                is_local.set(controller.input_index);
            }
        }
        self.is_certain.items[tick].setUnion(is_local);
    }
}

pub fn remoteUpdate(self: *Self, allocator: std.mem.Allocator, player: u32, new_state: input.PlayerInputState, tick: u64) !bool {
    //if (tick < self.newest_remote_frame) {
    //    std.debug.print("newest_remote_frame: {d}, tick: {d}\n", .{self.newest_remote_frame, tick});
    //    @panic("the inputs came out of order");
    //}

    try self.extendTimeline(allocator, tick);
    //std.debug.print("remote update for player {d} at tick {d}\n", .{player, tick});
    for (self.buttons.items[tick..], self.is_certain.items[tick..]) |*frame, is_certain| {
        if (is_certain.isSet(player)) {
            // We are already certain of this input. Nothing to do here.
            // This is probably just the server re-broadcasting the input that the client sent it.
            // But it could also be an error... Oh well!
            return false;
        }
        frame[player] = new_state;
    }

    // We will not let anyone override this input in the future.
    // It is locked in for consistency.
    // Setting this flag also lets us know that it is worth sending in the net-code.
    self.is_certain.items[tick].set(player);

    self.newest_remote_frame = tick;
    return true;
}

pub fn dumpInputs(self: *Self, writer: anytype) !void {
    try writer.print("input frames: {d}\n", .{self.buttons.items.len});
    for (self.buttons.items, self.is_certain.items, 0..) |inputs, is_certain, frame_index| {
        try writer.print("{d}: ", .{frame_index});
        for (inputs, 0..) |inp, i| {
            const on = if (is_certain.isSet(i)) "YES" else "IDK";
            try writer.print("{s}({s}) ", .{inp.dpad.shortDebugName(), on});
        }
        try writer.print("\n", .{});
    }
}
