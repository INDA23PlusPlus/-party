const rl = @import("raylib");

pub fn main() void {
    var window_width: i32 = 800;
    var window_height: i32 = 640;

    // Init
    rl.setTraceLogLevel(rl.TraceLogLevel.log_error);
    rl.setConfigFlags(rl.ConfigFlags.flag_window_resizable);
    rl.initWindow(800, 640, "++party");
    rl.setTargetFPS(60);

    // Game loop
    while(true) {
        // Exit
        if(rl.windowShouldClose() or rl.isKeyPressed(rl.KeyboardKey.key_escape)) {
            break;
        }

        // Window resize
        if(rl.isWindowResized()) {
            window_width = rl.getRenderWidth();
            window_height = rl.getRenderHeight();
        }

        // Update goes here

        rl.beginDrawing();
        
        // Render goes here

        rl.endDrawing();
    }

    rl.closeWindow();
}
