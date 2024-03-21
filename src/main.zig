const rl = @import("raylib");
const win = @import("window.zig");
const input = @import("input.zig");

pub fn main() void {
    var window = win.Window.init(1920, 1080);
    defer window.deinit();

    // Game loop
    while (window.running) {

        // Update stuff here
        input.update();
        window.update();

        rl.beginDrawing();

        // Draw stuff here
        rl.clearBackground(rl.Color.white);
        rl.drawText("++party! :D", 8, 8, 96, rl.Color.blue);

        rl.endDrawing();
    }
}
