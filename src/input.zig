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
        if (self.pressed()) { // TODO: Shouldn't this just be isDown? Won't it be pressed for one extra tick as it is?
            self.press_tick = current_tick;
        }
        if (self.released()) {
            self.release_tick = current_tick;
        }
    }

    pub fn cmp(self: *const ButtonState, other: ButtonState) i32 {
        if (self.is_down and !other.is_down) {
            return 1;
        }
        if (!self.is_down and other.is_down) {
            return -1;
        }
        return 0;
    }

    // Possibly more/less performant depending on the compiler.
    pub inline fn cmp_branchless(self: ButtonState, other: ButtonState) i32 {
        const a = @intFromBool(self.is_down) > @intFromBool(other.is_down);
        const b = @intFromBool(self.is_down) < @intFromBool(other.is_down);

        return @intFromBool(a) - @intFromBool(b);
    }
};

pub const PlayerInputState = struct {
    is_local: bool = false,
    is_connected: bool = false,
    a: ButtonState = .{},
    b: ButtonState = .{},
    up: ButtonState = .{},
    down: ButtonState = .{},
    left: ButtonState = .{},
    right: ButtonState = .{},

    pub fn horizontal(self: *const PlayerInputState) i32 {
        return self.right.cmp(self.left);
    }

    pub fn vertical(self: *const PlayerInputState) i32 {
        return self.down.cmp(self.up);
    }
};

pub const InputState = [constants.max_player_count]PlayerInputState;

pub const default_input_state: InputState = [_]PlayerInputState{.{}} ** constants.max_player_count;
