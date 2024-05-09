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
        } else if (right and !left) {
            return .NorthEast;
        } else {
            return .North;
        }
    } else if (down and !up) {
        if (left and !right) {
            return .SouthWest;
        } else if (right and !left) {
            return .SouthEast;
        } else {
            return .South;
        }
    } else {
        if (left and !right) {
            return .West;
        } else if (right and !left) {
            return .East;
        } else {
            return .None;
        }
    }
}

inline fn keyboardKeyToButtonState(key: rl.KeyboardKey) input.ButtonState {
    if (rl.isKeyUp(key)) {
        if (rl.isKeyReleased(key)) return .Released;

        return .NotHeld;
    }

    if (rl.isKeyPressed(key)) return .Pressed;

    return .Held;
}

inline fn gamepadButtonToButtonState(gamepad: i32, button: rl.GamepadButton) input.ButtonState {
    if (rl.isGamepadButtonUp(gamepad, button)) {
        if (rl.isGamepadButtonReleased(gamepad, button)) return .Released;

        return .NotHeld;
    }

    if (rl.isGamepadButtonPressed(gamepad, button)) return .Pressed;

    return .Held;
}

inline fn pollKeyboardDPads(key_up: rl.KeyboardKey, key_down: rl.KeyboardKey, key_left: rl.KeyboardKey, key_right: rl.KeyboardKey) input.InputDirection {
    const up = rl.isKeyDown(key_up);
    const down = rl.isKeyDown(key_down);
    const left = rl.isKeyDown(key_left);
    const right = rl.isKeyDown(key_right);
    return fourBoolsToDirection(up, down, left, right);
}

fn pollKeyboard1(previous: input.PlayerInputState) input.PlayerInputState {
    _ = previous;
    const dpad = pollKeyboardDPads(rl.KeyboardKey.key_w, rl.KeyboardKey.key_s, rl.KeyboardKey.key_a, rl.KeyboardKey.key_d);
    const a = keyboardKeyToButtonState(rl.KeyboardKey.key_z); // pressedToButtonState(rl.isKeyPressed(rl.KeyboardKey.key_z), previous.button_a);
    const b = keyboardKeyToButtonState(rl.KeyboardKey.key_x); // pressedToButtonState(rl.isKeyPressed(rl.KeyboardKey.key_x), previous.button_b);
    return .{
        .dpad = dpad,
        .button_a = a,
        .button_b = b,
    };
}

fn pollKeyboard2(previous: input.PlayerInputState) input.PlayerInputState {
    _ = previous;
    const dpad = pollKeyboardDPads(rl.KeyboardKey.key_i, rl.KeyboardKey.key_k, rl.KeyboardKey.key_j, rl.KeyboardKey.key_l);
    const a = keyboardKeyToButtonState(rl.KeyboardKey.key_n);
    const b = keyboardKeyToButtonState(rl.KeyboardKey.key_m);
    return .{
        .dpad = dpad,
        .button_a = a,
        .button_b = b,
    };
}

fn pollGamepad(gamepad: i32, previous: input.PlayerInputState) input.PlayerInputState {
    _ = previous;
    if (!rl.isGamepadAvailable(gamepad)) return .{ .dpad = .Disconnected };

    const a = gamepadButtonToButtonState(gamepad, rl.GamepadButton.gamepad_button_right_face_down); // pressedToButtonState(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_right_face_down), previous.button_a);
    const b = gamepadButtonToButtonState(gamepad, rl.GamepadButton.gamepad_button_right_face_right); // pressedToButtonState(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_right_face_right), previous.button_b);

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

pub fn autoAssign(controllers: []Controller, previous: input.AllPlayerButtons) void {
    for (0..8) |i| {
        // This controller has an index, skip it.
        if (controllers[i].input_index < 8) {
            continue;
        }

        var input_state: input.PlayerInputState = undefined;
        switch (i) {
            0 => {
                input_state = pollKeyboard1(previous[i]);
            },
            1 => {
                input_state = pollKeyboard2(previous[i]);
            },
            else => {
                input_state = pollGamepad(@intCast(i), previous[i]);
            },
        }

        // Pressed A/B, trying to join.
        if (input_state.button_a.is_down() or input_state.button_b.is_down()) {
            // Find indices that are available, first is best
            var unavailable = [_]usize{std.math.maxInt(usize)} ** 8;
            for (controllers) |con| {
                if (con.input_index < 8) {
                    unavailable[con.input_index] = con.input_index;
                }
            }
            const available = std.mem.indexOfScalar(usize, &unavailable, std.math.maxInt(usize));
            if (available) |av| {
                std.debug.print("Controller {} joined with id {}\n", .{ i, av });
                controllers[i].input_index = av;
            }
        }
    }
}
