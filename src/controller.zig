const std = @import("std");
const rl = @import("raylib");
const input = @import("input.zig");
const constants = @import("constants.zig");

const Controller = @This();
pub const DefaultControllers: [constants.max_controller_count]Controller = [_]Controller{.{}} ** constants.max_controller_count;

input_index: usize = std.math.maxInt(usize),


fn poll_keyboard1(state: *input.PlayerInputState, current_tick: usize) void {
    state.is_local = true;
    state.is_connected = true;
    state.a.set(rl.isKeyDown(rl.KeyboardKey.key_x), current_tick);
    state.b.set(rl.isKeyDown(rl.KeyboardKey.key_z), current_tick);
    state.up.set(rl.isKeyDown(rl.KeyboardKey.key_w), current_tick);
    state.down.set(rl.isKeyDown(rl.KeyboardKey.key_s), current_tick);
    state.left.set(rl.isKeyDown(rl.KeyboardKey.key_a), current_tick);
    state.right.set(rl.isKeyDown(rl.KeyboardKey.key_d), current_tick);
}

fn poll_keyboard2(state: *input.PlayerInputState, current_tick: usize) void {
    state.is_local = true;
    state.is_connected = true;
    state.a.set(rl.isKeyDown(rl.KeyboardKey.key_n), current_tick);
    state.b.set(rl.isKeyDown(rl.KeyboardKey.key_m), current_tick);
    state.up.set(rl.isKeyDown(rl.KeyboardKey.key_i), current_tick);
    state.down.set(rl.isKeyDown(rl.KeyboardKey.key_k), current_tick);
    state.left.set(rl.isKeyDown(rl.KeyboardKey.key_j), current_tick);
    state.right.set(rl.isKeyDown(rl.KeyboardKey.key_l), current_tick);
}

fn poll_gamepad(gamepad: i32, state: *input.PlayerInputState, current_tick: usize) void {
    state.is_local = true;
    state.is_connected = rl.isGamepadAvailable(gamepad);
    state.a.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_right_face_down), current_tick);
    state.b.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_right_face_right), current_tick);
    state.up.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_up), current_tick);
    state.down.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_down), current_tick);
    state.left.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_left), current_tick);
    state.right.set(rl.isGamepadButtonDown(gamepad, rl.GamepadButton.gamepad_button_left_face_right), current_tick);
}

// Polls the state of all input devices at the current time.
pub fn poll(controllers: []Controller, state: *input.InputState, current_tick: usize) void {
    const controller1 = controllers[0].input_index;
    if (controller1 < state.len) {
        poll_keyboard1(&state[controller1], current_tick);
    }

    const controller2 = controllers[1].input_index;
    if (controller2 < state.len) {
        poll_keyboard2(&state[controller2], current_tick);
    }

    for (controllers[2..], 0..) |controller, gamepad_id| {
        const controller_n = controller.input_index;
        if (controller_n >= state.len) {
            continue;
        }
        poll_gamepad(@intCast(gamepad_id), &state[controller_n], current_tick);
    }
}
