const std = @import("std");
const rl = @import("raylib");
const time = @import("time.zig");

pub const MAX_CONTROLLERS = 8;
var m_controllers: [MAX_CONTROLLERS]?Controller = .{ null, null, null, null, null, null, null, null }; // there has to be a better way to do this

// Maybe?
// const Controls = struct {
//     primary: *const fn () bool,
//     secondary: *const fn () bool,
//     up: *const fn () bool,
//     down: *const fn () bool,
//     left: *const fn () bool,
//     right: *const fn () bool,
// };

pub fn controller(id: usize) ?Controller {
    return m_controllers[id];
}

pub fn controllers() [MAX_CONTROLLERS]?Controller {
    return m_controllers;
}

pub fn poll() void {
    for (0..MAX_CONTROLLERS) |id| {
        if (rl.isGamepadAvailable(@intCast(id)) and m_controllers[id] == null) {
            m_controllers[id] = Controller.init(id);
            std.debug.print("\ncontroller {} connected\n", .{id});
        }

        if (!rl.isGamepadAvailable(@intCast(id)) and m_controllers[id] != null) {
            m_controllers[id] = null;
            std.debug.print("\ncontroller {} disconnected\n", .{id});
        }

        if (m_controllers[id] != null) {
            m_controllers[id].?.poll();
        }
    }
}

pub fn post() void {
    for (0..MAX_CONTROLLERS) |id| {
        if (m_controllers[id] != null) {
            m_controllers[id].?.post();
        }
    }
}

pub const Button = struct {
    const Self = @This();

    m_isDown: bool,
    m_wasDown: bool,
    m_pressTime: u64,

    fn init() Button {
        return .{
            .m_isDown = false,
            .m_wasDown = false,
            .m_pressTime = 0,
        };
    }

    pub fn down(self: *const Self) bool {
        return self.m_isDown;
    }

    pub fn pressed(self: *const Self) bool {
        return self.m_isDown and !self.m_wasDown;
    }

    pub fn released(self: *const Self) bool {
        return !self.m_isDown and self.m_wasDown;
    }

    pub fn duration(self: *const Self) u64 {
        if (self.down()) {
            return time.get() - self.m_pressTime;
        }
        return 0;
    }

    fn poll(self: *Self, isDown: bool) void {
        self.m_isDown = isDown;
        if (self.pressed()) {
            self.m_pressTime = time.get();
        }
    }

    fn post(self: *Self) void {
        self.m_wasDown = self.m_isDown;
    }
};

pub const Controller = struct {
    const Self = @This();

    m_id: usize,
    m_primary: Button,
    m_secondary: Button,
    m_up: Button,
    m_down: Button,
    m_left: Button,
    m_right: Button,

    fn init(m_id: usize) Controller {
        return .{
            .m_id = m_id,
            .m_primary = Button.init(),
            .m_secondary = Button.init(),
            .m_up = Button.init(),
            .m_down = Button.init(),
            .m_left = Button.init(),
            .m_right = Button.init(),
        };
    }

    // Controller ID.
    pub fn id(self: *const Self) usize {
        return self.m_id;
    }

    // Primary button input.
    pub fn primary(self: *const Self) Button {
        return self.m_primary;
    }

    // Secondary button input.
    pub fn secondary(self: *const Self) Button {
        return self.m_secondary;
    }

    // Directional up input.
    pub fn up(self: *const Self) Button {
        return self.m_up;
    }

    // Directional down input.
    pub fn down(self: *const Self) Button {
        return self.m_down;
    }

    // Directional left input.
    pub fn left(self: *const Self) Button {
        return self.m_left;
    }

    // Directional right input.
    pub fn right(self: *const Self) Button {
        return self.m_right;
    }

    // Horizontal direction delta; digital. Left = -1, Neutral = 0, Right = 1.
    pub fn horizontal(self: *const Self) i32 {
        return @as(i32, @intFromBool(self.right().down())) - @as(i32, @intFromBool(self.left().down()));
    }

    // Vertical direction delta; digital. Down = -1, Neutral = 0, Up = 1.
    pub fn vertical(self: *const Self) i32 {
        return @as(i32, @intFromBool(self.up().down())) - @as(i32, @intFromBool(self.down().down()));
    }

    fn poll(self: *Self) void {
        // No keyboard input for now
        // self.m_primary.poll(rl.isKeyDown(self.m_keymap.primary) or rl.isGamepadButtonDown(@intCast(self.m_id), rl.GamepadButton.gamepad_button_right_face_down));
        // self.m_secondary.poll(rl.isKeyDown(rl.KeyboardKey.key_z) or rl.isGamepadButtonDown(@intCast(self.m_id), rl.GamepadButton.gamepad_button_right_face_right));
        // self.m_down.poll(rl.isKeyDown(rl.KeyboardKey.key_down) or rl.isKeyDown(rl.KeyboardKey.key_s) or rl.isGamepadButtonDown(@intCast(self.m_id), rl.GamepadButton.gamepad_button_left_face_down));
        // self.m_left.poll(rl.isKeyDown(rl.KeyboardKey.key_left) or rl.isKeyDown(rl.KeyboardKey.key_a) or rl.isGamepadButtonDown(@intCast(self.m_id), rl.GamepadButton.gamepad_button_left_face_left));
        // self.m_right.poll(rl.isKeyDown(rl.KeyboardKey.key_right) or rl.isKeyDown(rl.KeyboardKey.key_d) or rl.isGamepadButtonDown(@intCast(self.m_id), rl.GamepadButton.gamepad_button_left_face_right));
        // self.m_up.poll(rl.isKeyDown(rl.KeyboardKey.key_up) or rl.isKeyDown(rl.KeyboardKey.key_w) or rl.isGamepadButtonDown(@intCast(self.m_id), rl.GamepadButton.gamepad_button_left_face_up));
        self.m_primary.poll(rl.isGamepadButtonDown(@intCast(self.m_id), rl.GamepadButton.gamepad_button_right_face_down));
        self.m_secondary.poll(rl.isGamepadButtonDown(@intCast(self.m_id), rl.GamepadButton.gamepad_button_right_face_right));
        self.m_down.poll(rl.isGamepadButtonDown(@intCast(self.m_id), rl.GamepadButton.gamepad_button_left_face_down));
        self.m_left.poll(rl.isGamepadButtonDown(@intCast(self.m_id), rl.GamepadButton.gamepad_button_left_face_left));
        self.m_right.poll(rl.isGamepadButtonDown(@intCast(self.m_id), rl.GamepadButton.gamepad_button_left_face_right));
        self.m_up.poll(rl.isGamepadButtonDown(@intCast(self.m_id), rl.GamepadButton.gamepad_button_left_face_up));
    }

    fn post(self: *Self) void {
        self.m_primary.post();
        self.m_secondary.post();
        self.m_down.post();
        self.m_left.post();
        self.m_right.post();
        self.m_up.post();
    }
};
