const std = @import("std");
const rl = @import("raylib");
const fi = @import("frame_info.zig");

var posy: i32 = 0;

pub fn update(info: *const fi.FrameInfo) void {
    posy = @intFromFloat(@sin(3.0 * info.time) * 100.0);
    posy = @divFloor(info.height, 2) + posy;
}

pub fn render(info: *const fi.FrameInfo) void {
    rl.clearBackground(rl.Color.gray);
    rl.drawCircle(@divFloor(info.width, 2), 
                  posy, 200, 
                  rl.Color.fromHSV(@mod(36.0 * info.time, 360.0), 0.6, 1.0));
}