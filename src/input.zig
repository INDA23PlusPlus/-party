const std = @import("std");
const rl = @import("raylib");
const time = @import("time.zig");

var states: [8]InputState = .{ .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{} };

// Gets an input struct from a controller ID. The ID should be obtained from the controller component.
pub fn get(id: usize) InputState {
    return states[id];
}

// Polls the state of all input devices at the current time.
pub fn poll() void {
    poll_keyboard1(&states[0]);
    poll_keyboard2(&states[1]);
    poll_gamepad(0, &states[2]);
    poll_gamepad(1, &states[3]);
    poll_gamepad(2, &states[4]);
    poll_gamepad(3, &states[5]);
    poll_gamepad(4, &states[6]);
    poll_gamepad(5, &states[7]);
}

const InputState = struct {
    isLocal: bool = false,
    isConnected: bool = false,
    A: ButtonState = .{},
    B: ButtonState = .{},
    up: ButtonState = .{},
    down: ButtonState = .{},
    left: ButtonState = .{},
    right: ButtonState = .{},

    pub fn horizontal(self: *const InputState) i32 {
        return self.right.cmp(self.left);
    }

    pub fn vertical(self: *const InputState) i32 {
        return self.down.cmp(self.up);
    }
};

const ButtonState = struct {
    isDown: bool = false,
    wasDown: bool = false,
    pressTime: u64 = 0,

    pub fn duration(self: *const ButtonState) u64 {
        if (self.isDown) {
            return time.get() - self.pressTime;
        }
        return 0;
    }

    pub fn pressed(self: *const ButtonState) bool {
        return self.isDown and !self.wasDown;
    }

    pub fn released(self: *const ButtonState) bool {
        return !self.isDown and self.wasDown;
    }

    pub fn set(self: *ButtonState, value: bool) void {
        self.wasDown = self.isDown;
        self.isDown = value;
        if (self.pressed()) {
            self.pressTime = time.get();
        }
    }

    pub fn cmp(self: *const ButtonState, other: ButtonState) i32 {
        if (self.isDown and !other.isDown) {
            return 1;
        }
        if (!self.isDown and other.isDown) {
            return -1;
        }
        return 0;
    }
};

fn poll_keyboard1(state: *InputState) void {
    state.isLocal = true;
    state.isConnected = true;
    state.A.set(rl.isKeyDown(rl.KeyboardKey.key_x));
    state.B.set(rl.isKeyDown(rl.KeyboardKey.key_z));
    state.up.set(rl.isKeyDown(rl.KeyboardKey.key_w));
    state.down.set(rl.isKeyDown(rl.KeyboardKey.key_s));
    state.left.set(rl.isKeyDown(rl.KeyboardKey.key_a));
    state.right.set(rl.isKeyDown(rl.KeyboardKey.key_d));
}

fn poll_keyboard2(state: *InputState) void {
    state.isLocal = true;
    state.isConnected = true;
    state.A.set(rl.isKeyDown(rl.KeyboardKey.key_n));
    state.B.set(rl.isKeyDown(rl.KeyboardKey.key_m));
    state.up.set(rl.isKeyDown(rl.KeyboardKey.key_i));
    state.down.set(rl.isKeyDown(rl.KeyboardKey.key_k));
    state.left.set(rl.isKeyDown(rl.KeyboardKey.key_j));
    state.right.set(rl.isKeyDown(rl.KeyboardKey.key_l));
}

fn poll_gamepad(gamepad: i32, state: *InputState) void {
    state.isLocal = true;
    state.isConnected = rl.isGamepadAvailable(gamepad);
    state.A.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_right_face_down));
    state.B.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_right_face_right));
    state.up.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_up));
    state.down.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_down));
    state.left.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_left));
    state.right.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_right));
}
