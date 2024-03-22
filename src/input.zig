// TODO: Custom button struct with Down, Pressed, Released and HoldDuration parameters.

const std = @import("std");
const rl = @import("raylib");

pub const ControlScheme = enum { Keyboard, Gamepad };

// Primary button
pub fn A() bool {
    return inputState.aButton;
}

// Secondary button
pub fn B() bool {
    inputState.bButton;
}

// Analog DPad delta in range [-1.0, 1.0]
pub fn DPad() rl.Vector2 {
    return inputState.dPad;
}

const InputState = struct {
    const Self = @This();
    aButton: bool,
    bButton: bool,
    dPad: rl.Vector2,
    pub fn init() InputState {
        return .{
            .aButton = false,
            .bButton = false,
            .dPad = rl.Vector2.init(0.0, 0.0),
        };
    }
};

var controlScheme: ControlScheme = ControlScheme.Keyboard;
var inputState: InputState = InputState.init();

fn getGamepadState() InputState {
    return .{
        .aButton = rl.isGamepadButtonDown(0, rl.GamepadButton.gamepad_button_right_face_down),
        .bButton = rl.isGamepadButtonDown(0, rl.GamepadButton.gamepad_button_right_face_right),
        .dPad = rl.Vector2.init(
            rl.getGamepadAxisMovement(0, @intFromEnum(rl.GamepadAxis.gamepad_axis_left_x)),
            rl.getGamepadAxisMovement(0, @intFromEnum(rl.GamepadAxis.gamepad_axis_left_y)),
        ),
    };
}

fn getKeyboardState() InputState {
    const left: bool = rl.isKeyDown(rl.KeyboardKey.key_left) or rl.isKeyDown(rl.KeyboardKey.key_a);
    const right: bool = rl.isKeyDown(rl.KeyboardKey.key_right) or rl.isKeyDown(rl.KeyboardKey.key_d);
    const up: bool = rl.isKeyDown(rl.KeyboardKey.key_up) or rl.isKeyDown(rl.KeyboardKey.key_w);
    const down: bool = rl.isKeyDown(rl.KeyboardKey.key_down) or rl.isKeyDown(rl.KeyboardKey.key_s);
    const dx: i32 = @as(i32, @intFromBool(right)) - @as(i32, @intFromBool(left));
    const dy: i32 = @as(i32, @intFromBool(up)) - @as(i32, @intFromBool(down));
    return .{
        .aButton = rl.isKeyDown(rl.KeyboardKey.key_x),
        .bButton = rl.isKeyDown(rl.KeyboardKey.key_z),
        .dPad = rl.Vector2.init(@floatFromInt(dx), @floatFromInt(dy)),
    };
}

pub fn update() void {
    inputState = switch (controlScheme) {
        ControlScheme.Keyboard => getKeyboardState(),
        ControlScheme.Gamepad => getGamepadState(),
    };
}
