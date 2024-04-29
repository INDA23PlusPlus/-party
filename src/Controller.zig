const std = @import("std");
const rl = @import("raylib");
const input = @import("input.zig");
const constants = @import("constants.zig");

const Controller = @This();
pub const DefaultControllers: [constants.max_controller_count]Controller = [_]Controller{.{}} ** constants.max_controller_count;

input_index: usize = std.math.maxInt(usize),

inline fn fourBoolsToDirection(up: bool, down: bool, left: bool, right: bool) input.InputDirection {
    if (up and !down) {
        if (left and !right) {
            return .NorthWest;
        }
        if (right and !left) {
            return .NorthEast;
        }
        return .North;
    } else if (down and !up) {
        if (left and !right) {
            return .SouthWest;
        }
        if (right and !left) {
            return .SouthEast;
        }
        return .South;
    }

    if (left and !right) {
        return .West;
    }
    if (right and !left) {
        return .East;
    }
    return .None;
}

inline fn pressedToButtonState(pressed: bool, previous: input.ButtonState) input.ButtonState {
    if (previous.is_down() and pressed) {
        return .Held;
    }
    if (pressed) {
        return .Pressed;
    }
    return .Released;
}

inline fn pollKeyboardDPads(key_up: rl.KeyboardKey, key_down: rl.KeyboardKey, key_left: rl.KeyboardKey, key_right: rl.KeyboardKey) input.InputDirection {
    const up = rl.isKeyDown(key_up);
    const down = rl.isKeyDown(key_down);
    const left = rl.isKeyDown(key_left);
    const right = rl.isKeyDown(key_right);
    //std.debug.print("{} {} {} {}\n", .{ up, down, left, right });
    return fourBoolsToDirection(up, down, left, right);
}

fn pollKeyboard1(previous: input.PlayerInputState) input.PlayerInputState {
    const dpad = pollKeyboardDPads(rl.KeyboardKey.key_w, rl.KeyboardKey.key_s, rl.KeyboardKey.key_a, rl.KeyboardKey.key_d);
    const a = pressedToButtonState(rl.isKeyPressed(rl.KeyboardKey.key_z), previous.button_a); // Support the button being released and pressed again inbetween frames using isKeyPressed.
    const b = pressedToButtonState(rl.isKeyPressed(rl.KeyboardKey.key_x), previous.button_b);
    return .{
        .dpad = dpad,
        .button_a = a,
        .button_b = b,
    };
    //    state.is_local = true;
    //    state.is_connected = true;
    //
    //    state.button_a.set(rl.isKeyDown(rl.KeyboardKey.key_x), current_tick);
    //    state.button_b.set(rl.isKeyDown(rl.KeyboardKey.key_z), current_tick);
    //    state.button_up.set(rl.isKeyDown(rl.KeyboardKey.key_w), current_tick);
    //    state.button_down.set(rl.isKeyDown(rl.KeyboardKey.key_s), current_tick);
    //    state.button_left.set(rl.isKeyDown(rl.KeyboardKey.key_a), current_tick);
    //    state.button_right.set(rl.isKeyDown(rl.KeyboardKey.key_d), current_tick);
}

fn pollKeyboard2(previous: input.PlayerInputState) input.PlayerInputState {
    const dpad = pollKeyboardDPads(rl.KeyboardKey.key_i, rl.KeyboardKey.key_k, rl.KeyboardKey.key_j, rl.KeyboardKey.key_l);
    const a = pressedToButtonState(rl.isKeyPressed(rl.KeyboardKey.key_n), previous.button_a);
    const b = pressedToButtonState(rl.isKeyPressed(rl.KeyboardKey.key_m), previous.button_b);
    return .{
        .dpad = dpad,
        .button_a = a,
        .button_b = b,
    };
    //    state.is_local = true;
    //    state.is_connected = true;
    //    state.button_a.set(rl.isKeyDown(rl.KeyboardKey.key_n), current_tick);
    //    state.button_b.set(rl.isKeyDown(rl.KeyboardKey.key_m), current_tick);
    //    state.button_up.set(rl.isKeyDown(rl.KeyboardKey.key_i), current_tick);
    //    state.button_down.set(rl.isKeyDown(rl.KeyboardKey.key_k), current_tick);
    //    state.button_left.set(rl.isKeyDown(rl.KeyboardKey.key_j), current_tick);
    //    state.button_right.set(rl.isKeyDown(rl.KeyboardKey.key_l), current_tick);
}

fn pollGamepad(gamepad: i32, previous: input.PlayerInputState) input.PlayerInputState {
    if (!rl.isGamepadAvailable(gamepad)) {
        return .{
            .dpad = .Disconnected,
        };
    }

    const a = pressedToButtonState(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_right_face_down), previous.button_a);
    const b = pressedToButtonState(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_right_face_right), previous.button_b);
    const up = rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_up);
    const down = rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_down);
    const left = rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_left);
    const right = rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_right);

    const dpad = fourBoolsToDirection(up, down, left, right);

    return .{
        .dpad = dpad,
        .button_a = a,
        .button_b = b,
    };

    //state.is_local = true;
    //state.is_connected = rl.isGamepadAvailable(gamepad);
    //state.button_a.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_right_face_down), current_tick);
    //state.button_b.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_right_face_right), current_tick);
    //state.button_up.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_up), current_tick);
    //state.button_down.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_down), current_tick);
    //state.button_left.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_left), current_tick);
    //state.button_right.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_right), current_tick);
}

// Polls the state of all input devices at the current time.
pub fn poll(controllers: []Controller, previous: input.AllPlayerButtons) input.AllPlayerButtons {
    // TODO: Also set the local variable somewhere...

    var result = previous;
    const controller1 = controllers[0].input_index;
    if (controller1 < result.len) {
        result[controller1] = pollKeyboard1(previous[controller1]);
    }

    const controller2 = controllers[1].input_index;
    if (controller2 < result.len) {
        result[controller2] = pollKeyboard2(previous[controller2]);
    }

    for (controllers[2..], 0..) |controller, gamepad_id| {
        const controller_n = controller.input_index;
        if (controller_n >= result.len) {
            continue;
        }
        result[controller_n] = pollGamepad(@intCast(gamepad_id), previous[controller_n]);
    }
    return result;
}
