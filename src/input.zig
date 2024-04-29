const constants = @import("constants.zig");
const std = @import("std");

// TODO: We could add a NoneHeld in order to skip checking previous frames for 'instant' dpad movement.
pub const InputDirection = enum(u4) { None, East, North, West, South, NorthEast, NorthWest, SouthWest, SouthEast, Disconnected };
pub const ButtonState = enum(u2) {
    Pressed,
    Held,
    Released,
    pub fn is_down(self: ButtonState) bool {
        // Currently only used in one place...
        return self == .Pressed or self == .Held;
    }
};
pub const PlayerInputState = packed struct {
    dpad: InputDirection = .Disconnected,
    button_a: ButtonState = .Released,
    button_b: ButtonState = .Released,

    pub fn is_connected(self: PlayerInputState) bool {
        // TODO: Maybe it should be removed in the future once we've settled into an input struct we like...
        return self.dpad != .Disconnected;
    }

    pub fn horizontal(self: PlayerInputState) i32 {
        return switch (self.dpad) {
            .East, .NorthEast, .SouthEast => 1,
            .West, .NorthWest, .SouthWest => -1,
            else => 0,
        };
    }

    pub fn vertical(self: PlayerInputState) i32 {
        return switch (self.dpad) {
            .North, .NorthEast, .NorthWest => 1,
            .South, .SouthEast, .SouthWest => -1,
            else => 0,
        };
    }
};

pub const AllPlayerButtons = [constants.max_player_count]PlayerInputState;
pub const IsLocalBitfield = std.bit_set.IntegerBitSet(constants.max_player_count);
pub const default_input_state = [_]PlayerInputState{.{}} ** constants.max_player_count;

pub const Timeline = struct {
    // Normally one would not make a struct for just one variable.
    // But we want to create some nice helper functions for the timeline.
    buttons: []AllPlayerButtons,
    pub fn latest(self: Timeline) AllPlayerButtons {
        if (self.buttons.len == 0) {
            return default_input_state;
        }
        return self.buttons[self.buttons.len - 1];
    }
    pub fn horizontal_pressed(time: Timeline, player: usize) i32 {
        std.debug.assert(player < constants.max_player_count);
        if (time.buttons.len < 2) {
            return 0;
        }
        const b = time.buttons;
        const previous = b[time.buttons.len - 2][player].horizontal();
        const resulting = b[time.buttons.len - 1][player].horizontal();
        if (previous == resulting) {
            return 0;
        }
        return resulting;
    }
    pub fn vertical_pressed(time: Timeline, player: usize) i32 {
        std.debug.assert(player < constants.max_player_count);
        if (time.buttons.len < 2) {
            return 0;
        }
        const b = time.buttons;
        const previous = b[time.buttons.len - 2][player].vertical();
        const resulting = b[time.buttons.len - 1][player].vertical();
        if (previous == resulting) {
            return 0;
        }
        return resulting;
    }
};

// const ButtonState = struct {
//     press_tick: u64 = 0,
//     release_tick: u64 = 0,
//     is_down: bool = false,
//     was_down: bool = false,
//
//     pub fn duration(self: *const ButtonState, current_tick: usize) u64 {
//         if (self.is_down) {
//             return current_tick - self.press_tick;
//         }
//
//         return 0;
//     }
//
//     pub fn pressed(self: *const ButtonState) bool {
//         return self.is_down and !self.was_down;
//     }
//
//     pub fn released(self: *const ButtonState) bool {
//         return !self.is_down and self.was_down;
//     }
//
//     pub fn set(self: *ButtonState, value: bool, current_tick: usize) void {
//         self.was_down = self.is_down;
//         self.is_down = value;
//         if (self.pressed()) {
//             self.press_tick = current_tick;
//         }
//         if (self.released()) {
//             self.release_tick = current_tick;
//         }
//     }
//
//     pub fn cmp(self: *const ButtonState, other: ButtonState) i32 {
//         return @as(i32, @intFromBool(self.is_down)) - @as(i32, @intFromBool(other.is_down));
//     }
// };
// pub const InputDirection = enum { None, East, North, West, South, NorthEast, NorthWest, SouthWest, SouthEast };

// pub const PlayerInputState = struct {
//     is_local: bool = false,
//     is_connected: bool = false,
//     button_a: ButtonState = .{},
//     button_b: ButtonState = .{},
//     button_up: ButtonState = .{},
//     button_down: ButtonState = .{},
//     button_left: ButtonState = .{},
//     button_right: ButtonState = .{},
//
//     pub fn horizontal(self: *const PlayerInputState) i32 {
//         return self.button_right.cmp(self.button_left);
//     }
//
//     pub fn vertical(self: *const PlayerInputState) i32 {
//         return self.button_up.cmp(self.button_down);
//     }
//
//     pub fn vertical_inv(self: *const PlayerInputState) i32 {
//         return -self.vertical();
//     }
//
//     pub fn direction(self: *const PlayerInputState) InputDirection {
//         return switch (self.vertical()) {
//             -1 => switch (self.horizontal()) {
//                 -1 => InputDirection.SouthWest,
//                 0 => InputDirection.South,
//                 1 => InputDirection.SouthEast,
//                 else => unreachable,
//             },
//             0 => switch (self.horizontal()) {
//                 -1 => InputDirection.West,
//                 0 => InputDirection.None,
//                 1 => InputDirection.East,
//                 else => unreachable,
//             },
//             1 => switch (self.horizontal()) {
//                 -1 => InputDirection.NorthWest,
//                 0 => InputDirection.North,
//                 1 => InputDirection.NorthEast,
//                 else => unreachable,
//             },
//             else => unreachable,
//         };
//     }
// };
