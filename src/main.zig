const rl = @import("raylib");
const win = @import("window.zig");

pub fn main() void {
    var window = win.Window.init(1920, 1080);
    defer window.deinit();

    // Game loop
    while(window.running) {
        // Updates goes here
        window.update();        

        rl.beginDrawing();
        
        // Rendering goes here

        rl.endDrawing();
    }

}
