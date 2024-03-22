const std = @import("std");
const rl = @import("raylib");

pub const Window = struct {
    const Self = @This();
    width: i32,
    height: i32,
    running: bool,
    suspended: bool,

    pub fn init(width: i32, height: i32) Window {
        rl.setTraceLogLevel(rl.TraceLogLevel.log_error);
        rl.initWindow(width, height, "++party");
        rl.setTargetFPS(60);

        std.debug.print("\nCreated a window. [{} x {}]\n", .{ width, height });
        return .{ .width = width, .height = height, .running = true, .suspended = false };
    }

    pub fn deinit(_: *Self) void {
        rl.closeWindow();
        std.debug.print("Goodbye...\n", .{});
    }

    pub fn update(self: *Self) void {
        if  (rl.windowShouldClose() or rl.isKeyPressed(rl.KeyboardKey.key_escape)) {
            self.running = false;
        }

        if  (rl.isWindowResized()) {
            self.width = rl.getRenderWidth();
            self.height = rl.getRenderHeight();
        }
    }
};

