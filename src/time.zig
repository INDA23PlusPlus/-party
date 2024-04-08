const std = @import("std");
const fixed = @import("math/fixed.zig");

// TODO: Move all of this into the World.

var frames: i48 = 0;
const fps: i16 = 60;

pub fn update() void {
    frames += 1;
}

pub fn get() fixed.F(48, 16) {
    return fixed.F(48, 16).init(frames, fps);
}
