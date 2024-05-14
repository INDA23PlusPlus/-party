// TODO: InputMerger would be a more obvious name.

const std = @import("std");
const input = @import("input.zig");
const constants = @import("constants.zig");
const Controller = @import("Controller.zig");
const Self = @This();

const InputStateArrayList = std.ArrayListUnmanaged(input.AllPlayerButtons);
const PlayerBitSet = std.bit_set.IntegerBitSet(constants.max_player_count);
const PlayerBitSetArrayList = std.ArrayListUnmanaged(PlayerBitSet);
const empty_player_bit_set = PlayerBitSet.initEmpty();
const full_player_bit_set = PlayerBitSet.initFull();

rw_lock: std.Thread.RwLock = .{},
buttons: InputStateArrayList,
is_certain: PlayerBitSetArrayList,

// TODO: Move this logic out of InputMerger.zig
newest_remote_frame: u64 = 0,

pub fn init(allocator: std.mem.Allocator) !Self {
    // We append one to each array because extendTimeline() must have at least one frame available
    // such that it can be used as inspiration for the rest of the timeline.
    var buttons = try InputStateArrayList.initCapacity(allocator, 1024);
    try buttons.append(allocator, input.default_input_state);

    // We are always certain of the zero frame as changes to it
    // should be ignored.
    var is_certain = try PlayerBitSetArrayList.initCapacity(allocator, 1024);
    try is_certain.append(allocator, full_player_bit_set);

    return .{
        .buttons = buttons,
        .is_certain = is_certain,
    };
}

pub fn extendTimeline(self: *Self, allocator: std.mem.Allocator, tick: u64) !void {
    if (tick + 1 < self.buttons.items.len) {
        // No need to extend the timeline.
        return;
    }

    const guess_buttons = self.buttons.getLast();
    const start = self.buttons.items.len;

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

pub fn localUpdate(self: *Self, controllers: []Controller, tick: u64) !void {
    if (tick < self.newest_remote_frame) {
        // No need to submit frames that happened.
        return;
    }

    // Make sure that extendTimeline() is called before.
    std.debug.assert(tick < self.buttons.items.len);
    const inputs = Controller.poll(controllers, self.buttons.items[tick]);
    var is_certain = self.is_certain.items[tick];
    for (controllers) |controller| {
        const player = controller.input_index;
        if (controller.isAssigned()) {
            if (is_certain.isSet(player)) {
                continue;
            }
            self.buttons.items[tick][player] = inputs[player];
            is_certain.set(player);
        }
    }
    self.is_certain.items[tick] = is_certain;
}

/// Returns true if the timeline was changed by this call.
pub fn remoteUpdate(self: *Self, allocator: std.mem.Allocator, player: u32, new_state: input.PlayerInputState, tick: u64) !bool {
    //if (tick < self.newest_remote_frame) {
    //    std.debug.print("newest_remote_frame: {d}, tick: {d}\n", .{self.newest_remote_frame, tick});
    //    @panic("the inputs came out of order");
    //}

    try self.extendTimeline(allocator, tick);

    // The amount of player inputs that were mutated by this call.
    var changes: u64 = 0;

    //std.debug.print("remote update for player {d} at tick {d}\n", .{player, tick});
    for (self.buttons.items[tick..], self.is_certain.items[tick..]) |*frame, is_certain| {
        if (is_certain.isSet(player)) {
            // We are already certain of this input. Nothing to do here.
            // This is probably just the server re-broadcasting the input that the client sent it.
            // But it could also be an error... Oh well!
            break;
        }
        if (std.meta.eql(frame[player], new_state)) {
            // No need to change this frame in particular.
            continue;
        }
        frame[player] = new_state;
        changes += 1;
    }

    // We will not let anyone override this input in the future.
    // It is locked in for consistency.
    // Setting this flag also lets us know that it is worth sending in the net-code.
    // We only set consistency for <tick> because future values are just "guesses".
    self.is_certain.items[tick].set(player);

    self.newest_remote_frame = @max(self.newest_remote_frame, tick);

    return changes != 0;
}

pub fn forceAutoAssign(self: *Self, tick: u64, controllers: []Controller, nth_controller: usize) bool {
    // Works a bit like localUpdate() but forces a controller to go online (for testing).

    // Make sure that extendTimeline() is called before.
    std.debug.assert(tick < self.buttons.items.len);
    var result = self.buttons.items[tick];

    // Find an available player.
    var unavailable = [_]usize{std.math.maxInt(usize)} ** constants.max_player_count;
    for (result, 0..) |inp, player_index| {
        if (inp.is_connected()) {
            unavailable[player_index] = player_index;
        }
    }
    const available = std.mem.indexOfScalar(usize, &unavailable, std.math.maxInt(usize));

    // Assign the available plyer to nth_controller.
    if (available) |available_player| {
        std.debug.print("Controller {} joined with id {}\n", .{ nth_controller, available_player });
        controllers[nth_controller].input_index = available_player;
        result[available_player].dpad = .None;
        self.buttons.items[tick] = result;
        return true;
    }
    return false;
}

pub fn autoAssign(self: *Self, controllers: []Controller, tick: u64) usize {
    var count: usize = 0;
    for (controllers, 0..) |controller, nth_controller| {
        if (controller.isAssigned()) {
            count += 1;
            continue;
        }
        if (!Controller.isActive(nth_controller)) {
            continue;
        }
        if (self.forceAutoAssign(tick, controllers, nth_controller)) {
            // Increase if we are successful in force-assigning this controller.
            // The if-statement will change our state a bit.
            count += 1;
        }
    }
    return count;
}

pub fn createChecksum(self: *Self) u32 {
    var hasher = std.hash.crc.Crc32.init();
    for (self.buttons.items) |buttons| {
        for (buttons) |button| {
            const state: u8 = @intFromEnum(button.dpad);
            hasher.update(&[_]u8{state});
        }
    }
    return hasher.final();
}

pub fn dumpInputs(self: *Self, writer: anytype) !void {
    const checksum = self.createChecksum();
    try writer.print("input frames: {d}\n", .{self.buttons.items.len});
    for (self.buttons.items, self.is_certain.items, 0..) |inputs, is_certain, frame_index| {
        try writer.print("{d:0>4}: ", .{frame_index});
        for (inputs, 0..) |inp, i| {
            const on = if (is_certain.isSet(i)) "+" else "?";
            try writer.print("{s}({s}) ", .{ inp.dpad.shortDebugName(), on });
        }
        try writer.print("\n", .{});
    }
    try writer.print("checksum: {x}\n", .{checksum});
}
