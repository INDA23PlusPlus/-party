// God save me

// TODO: Change the constants DPAD, A and B into struct literals and use this file as a struct.
// TODO: Rename to player_input. Create new file called input that is a struct containing an array sized max_player_count of player_input(s).
// TODO: After thinking aobut it. Perhaps this could be turned into a sort of queue. More thinking is needed.

const std = @import("std");
const rl = @import("raylib");
const time = @import("time.zig");

// Directional input.
pub const DPad = struct {
    var left: bool = false;
    var right: bool = false;
    var up: bool = false;
    var down: bool = false;

    // Digital horizontal delta; either -1 (Left) or 1 (Right).
    pub fn dx() i32 {
        return @as(i32, @intFromBool(right)) - @as(i32, @intFromBool(left));
    }

    // Digital vertical delta; either -1 (Down) or 1 (Up).
    pub fn dy() i32 {
        return @as(i32, @intFromBool(up)) - @as(i32, @intFromBool(down));
    }

    fn update() void {
        left = rl.isKeyDown(rl.KeyboardKey.key_left) or rl.isKeyDown(rl.KeyboardKey.key_a) or rl.isGamepadButtonDown(0, rl.GamepadButton.gamepad_button_left_face_left);
        right = rl.isKeyDown(rl.KeyboardKey.key_right) or rl.isKeyDown(rl.KeyboardKey.key_d) or rl.isGamepadButtonDown(0, rl.GamepadButton.gamepad_button_left_face_right);
        up = rl.isKeyDown(rl.KeyboardKey.key_up) or rl.isKeyDown(rl.KeyboardKey.key_w) or rl.isGamepadButtonDown(0, rl.GamepadButton.gamepad_button_left_face_up);
        down = rl.isKeyDown(rl.KeyboardKey.key_down) or rl.isKeyDown(rl.KeyboardKey.key_s) or rl.isGamepadButtonDown(0, rl.GamepadButton.gamepad_button_left_face_down);
    }
};

// Primary button input.
pub const A = struct {
    var m_isDown: bool = false;
    var m_wasDown: bool = false;
    var m_pressTime: u64 = 0;

    // How long the button has been down, in frames.
    pub fn duration() u64 {
        if (m_isDown) {
            return time.get().sub(m_pressTime);
        }
        return 0;
    }

    // Is the button down right now?
    pub fn down() bool {
        return m_isDown;
    }

    // Was the button pressed this frame?
    pub fn pressed() bool {
        return m_isDown and !m_wasDown;
    }

    // Was the button released this frame?
    pub fn released() bool {
        return !m_isDown and m_wasDown;
    }

    fn preUpdate() void {
        m_isDown = rl.isKeyDown(rl.KeyboardKey.key_x) or rl.isGamepadButtonDown(0, rl.GamepadButton.gamepad_button_right_face_down);
        if (pressed()) {
            m_pressTime = time.get();
        }
    }

    fn postUpdate() void {
        m_wasDown = m_isDown;
    }
};

// Secondary button input.
pub const B = struct {
    var m_isDown: bool = false;
    var m_wasDown: bool = false;
    var m_pressTime: u64 = 0;

    // How long the button has been down, in frames.
    pub fn duration() u64 {
        if (m_isDown) {
            return time.get().sub(m_pressTime);
        }
        return 0;
    }

    // Is the button down right now?
    pub fn down() bool {
        return m_isDown;
    }

    // Was the button pressed this frame?
    pub fn pressed() bool {
        return m_isDown and !m_wasDown;
    }

    // Was the button released this frame?
    pub fn released() bool {
        return !m_isDown and m_wasDown;
    }

    fn preUpdate() void {
        m_isDown = rl.isKeyDown(rl.KeyboardKey.key_z) or rl.isGamepadButtonDown(0, rl.GamepadButton.gamepad_button_right_face_right);
        if (pressed()) {
            m_pressTime = time.get();
        }
    }

    fn postUpdate() void {
        m_wasDown = m_isDown;
    }
};

pub fn preUpdate() void {
    A.preUpdate();
    B.preUpdate();
    DPad.update();
}

pub fn postUpdate() void {
    A.postUpdate();
    B.postUpdate();
}
