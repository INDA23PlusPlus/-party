const std = @import("std");

// TODO: Move all of this into the World.

var frames: u64 = 0;
const fps: u64 = 60;

pub fn update() void {
    frames += 1;
}

pub fn get() u64 {
    return frames;
}
