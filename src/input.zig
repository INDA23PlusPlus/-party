const std = @import("std");
const rl = @import("raylib");

// Primary button
pub fn A() bool {
    return a;
}

// Secondary button
pub fn B() bool {
    return b;
}

pub fn update() void {
    a = rl.isKeyDown(rl.KeyboardKey.key_z);
    b = rl.isKeyDown(rl.KeyboardKey.key_x);
}

var a: bool = false;
var b: bool = false;
