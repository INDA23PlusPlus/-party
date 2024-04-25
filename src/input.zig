const constants = @import("constants.zig");

const ButtonState = struct {
    press_tick: u64 = 0,
    release_tick: u64 = 0,
    is_down: bool = false,
    was_down: bool = false,

    pub fn duration(self: *const ButtonState, current_tick: usize) u64 {
        if (self.is_down) {
            return current_tick - self.press_tick;
        }

        return 0;
    }

    pub fn pressed(self: *const ButtonState) bool {
        return self.is_down and !self.was_down;
    }

    pub fn released(self: *const ButtonState) bool {
        return !self.is_down and self.was_down;
    }

    pub fn set(self: *ButtonState, value: bool, current_tick: usize) void {
        self.was_down = self.is_down;
        self.is_down = value;
        if (self.pressed()) {
            self.press_tick = current_tick;
        }
        if (self.released()) {
            self.release_tick = current_tick;
        }
    }

    pub fn cmp(self: *const ButtonState, other: ButtonState) i32 {
        return @as(i32, @intFromBool(self.is_down)) - @as(i32, @intFromBool(other.is_down));
    }
};

pub const InputDirection = enum { None, East, North, West, South, NorthEast, NorthWest, SouthWest, SouthEast };

pub const PlayerInputState = struct {
    is_local: bool = false,
    is_connected: bool = false,
    button_a: ButtonState = .{},
    button_b: ButtonState = .{},
    button_up: ButtonState = .{},
    button_down: ButtonState = .{},
    button_left: ButtonState = .{},
    button_right: ButtonState = .{},

    pub fn horizontal(self: *const PlayerInputState) i32 {
        return self.button_right.cmp(self.button_left);
    }

    pub fn vertical(self: *const PlayerInputState) i32 {
        return self.button_up.cmp(self.button_down);
    }

    pub fn vertical_inv(self: *const PlayerInputState) i32 {
        return -self.vertical();
    }

    pub fn direction(self: *const PlayerInputState) InputDirection {
        return switch (self.vertical()) {
            -1 => switch (self.horizontal()) {
                -1 => InputDirection.SouthWest,
                0 => InputDirection.South,
                1 => InputDirection.SouthEast,
                else => unreachable,
            },
            0 => switch (self.horizontal()) {
                -1 => InputDirection.West,
                0 => InputDirection.None,
                1 => InputDirection.East,
                else => unreachable,
            },
            1 => switch (self.horizontal()) {
                -1 => InputDirection.NorthWest,
                0 => InputDirection.North,
                1 => InputDirection.NorthEast,
                else => unreachable,
            },
            else => unreachable,
        };
    }
};

pub const InputState = [constants.max_player_count]PlayerInputState;

pub const default_input_state: InputState = [_]PlayerInputState{.{}} ** constants.max_player_count;
