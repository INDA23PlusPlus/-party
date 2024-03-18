const std = @import("std");
const rl = @import("raylib");
const fi = @import("frame_info.zig");

const text = "I unga, therefore I bunga.";

pub fn update(_: *const fi.FrameInfo) void { }

pub fn render(info: *const fi.FrameInfo) void {
    rl.clearBackground(rl.Color.sky_blue);
    rl.drawText(text,
                @divFloor(info.width, 2) - @divFloor(rl.measureText(text, 48), 2),
                @divFloor(info.height, 2) - 24,
                48, 
                rl.Color.white);
}