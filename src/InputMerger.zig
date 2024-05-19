// TODO: InputMerger would be a more obvious name.

const std = @import("std");
const input = @import("input.zig");
const constants = @import("constants.zig");
const Controller = @import("Controller.zig");
const Self = @This();

const InputStateArrayList = std.ArrayListUnmanaged(input.AllPlayerButtons);
const PlayerBitSetArrayList = std.ArrayListUnmanaged(input.PlayerBitSet);

rw_lock: std.Thread.RwLock = .{},
buttons: InputStateArrayList,
is_certain: PlayerBitSetArrayList,
is_server: bool = false, // Only used for debug prints. TODO: Remove in favour of a logger that is aware.

pub fn init(allocator: std.mem.Allocator) !Self {
    // We append one to each array because extendTimeline() must have at least one frame available
    // such that it can be used as inspiration for the rest of the timeline.
    var buttons = try InputStateArrayList.initCapacity(allocator, 1024);
    try buttons.append(allocator, input.default_input_state);

    // We are always certain of the zero frame as changes to it
    // should be ignored.
    var is_certain = try PlayerBitSetArrayList.initCapacity(allocator, 1024);
    try is_certain.append(allocator, input.full_player_bit_set);

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

    var guess_buttons = self.buttons.getLast();
    for (&guess_buttons) |*guess_player| {
        // It doesn't make sense for the prediction
        // to be that the player keeps button mashing at a pefect
        // 1 click per tick. So we adjust it.
        guess_player.button_a = guess_player.button_a.prediction();
        guess_player.button_b = guess_player.button_b.prediction();
    }
    const start = self.buttons.items.len;

    try self.buttons.ensureTotalCapacity(allocator, tick + 1);
    self.buttons.items.len = tick + 1;
    try self.is_certain.ensureTotalCapacity(allocator, tick + 1);
    self.is_certain.items.len = tick + 1;

    for (self.buttons.items[start..]) |*frame| {
        frame.* = guess_buttons;
    }

    for (self.is_certain.items[start..]) |*frame| {
        // We are always unsure when we are guessing.
        frame.* = input.empty_player_bit_set;
    }
}

pub fn localUpdate(self: *Self, controllers: []Controller, tick: u64) !void {
    // Make sure that extendTimeline() is called before.
    std.debug.assert(tick < self.buttons.items.len);

    var is_certain = self.is_certain.items[tick];
    for (controllers) |controller| {
        const player = controller.input_index;
        if (controller.isAssigned()) {
            if (is_certain.isSet(player)) {
                std.debug.print("warning local client is attempting to override previous input\n", .{});
                continue;
            }
            self.buttons.items[tick][player] = controller.polled_state;
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

    //std.debug.print("{} after remote update {b}\n", .{self.is_server, self.is_certain.items[tick].mask});

    return changes != 0;
}

pub fn forceAutoAssign(self: *Self, prev_tick: u64, controllers: []Controller, nth_controller: usize) bool {
    // Works a bit like localUpdate() but forces a controller to go online (for testing).

    // Make sure that extendTimeline() is called before.
    std.debug.assert(prev_tick < self.buttons.items.len);
    const inputs = self.buttons.items[prev_tick];

    // Find an available player.
    var unavailable = [_]bool{false} ** constants.max_player_count;
    for (inputs, 0..) |inp, player_index| {
        if (inp.is_connected()) {
            unavailable[player_index] = true;
        }
    }

    // We also check the controllers in case two or more controllers
    // were force-assigned the same tick. This way we avoid having
    // to change the timeline to prevent this.
    for (controllers) |controller| {
        if (controller.isAssigned()) {
            unavailable[controller.input_index] = true;
        }
    }
    const available = std.mem.indexOfScalar(bool, &unavailable, false);

    // Assign the available plyer to nth_controller.
    if (available) |available_player| {
        std.debug.print("Controller {} joined with id {}\n", .{ nth_controller, available_player });
        controllers[nth_controller].input_index = available_player;
        return true;
    }
    return false;
}

pub fn autoAssign(self: *Self, controllers: []Controller, prev_tick: u64) usize {
    var count: usize = 0;
    for (controllers, 0..) |controller, nth_controller| {
        if (controller.isAssigned()) {
            count += 1;
            continue;
        }
        if (!controller.givingInputs()) {
            continue;
        }
        if (self.forceAutoAssign(prev_tick, controllers, nth_controller)) {
            // Increase if we are successful in force-assigning this controller.
            // The if-statement will change our state a bit.
            count += 1;
        }
    }
    return count;
}

pub fn createChecksum(self: *Self, until: u64) u32 {
    var hasher = std.hash.crc.Crc32.init();
    for (0.., self.buttons.items) |tick_index, buttons| {
        if (tick_index > until) {
            break;
        }
        for (buttons) |button| {
            const state: u8 = @intFromEnum(button.dpad);
            const button_a: u8 = @intFromEnum(button.button_a);
            const button_b: u8 = @intFromEnum(button.button_b);
            hasher.update(&[_]u8{ state, button_a, button_b });
        }
    }
    return hasher.final();
}

pub fn dumpInputs(self: *Self, until: u64, writer: anytype) !void {
    const checksum = self.createChecksum(until);
    try writer.print("input frames: {d}\n", .{@min(self.buttons.items.len, until)});
    for (0.., self.buttons.items, self.is_certain.items) |tick_index, inputs, is_certain| {
        if (tick_index > until) {
            break;
        }
        try writer.print("{d:0>4}:", .{tick_index});
        for (inputs, 0..) |inp, i| {
            const on = if (is_certain.isSet(i)) "+" else "?";
            const a: u8 = @intFromEnum(inp.button_a);
            const b: u8 = @intFromEnum(inp.button_a);
            try writer.print(" {s}{d}{d}({s})", .{ inp.dpad.shortDebugName(), a, b, on });
        }
        try writer.print("\n", .{});
    }
    try writer.print("checksum: {x}\n", .{checksum});
}
