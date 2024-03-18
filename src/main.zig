const rl = @import("raylib");
const fi = @import("frame_info.zig");

const scene_a = @import("dummy_a.zig");
const scene_b = @import("dummy_b.zig");

pub fn main() void {
    var window_width: i32 = 800;
    var window_height: i32 = 640;
    var scene_index: i32 = 0;

    var update_func = &scene_a.update;
    var render_func = &scene_a.render;

    rl.setTraceLogLevel(rl.TraceLogLevel.log_error);
    rl.setConfigFlags(rl.ConfigFlags.flag_window_resizable);
    rl.initWindow(800, 640, "++party");
    rl.setTargetFPS(60);

    while(true) {
        if(rl.windowShouldClose() or rl.isKeyPressed(rl.KeyboardKey.key_escape)) {
            break;
        }

        if(rl.isWindowResized()) {
            window_width = rl.getRenderWidth();
            window_height = rl.getRenderHeight();
        }

        if(rl.isKeyPressed(rl.KeyboardKey.key_r)) {
            scene_index = @mod(scene_index + 1, 2);
            switch (scene_index) {
                0 => {
                    update_func = &scene_a.update;
                    render_func = &scene_a.render;
                },
                1 => {
                    update_func = &scene_b.update;
                    render_func = &scene_b.render;
                },
                else => { unreachable; }
            }
        }

        const info: fi.FrameInfo = .{ 
            .width = window_width, 
            .height = window_height, 
            .time = @floatCast(rl.getTime()),
            .dt = rl.getFrameTime()
        };
         
        update_func(&info);

        rl.beginDrawing();
        render_func(&info);
        rl.endDrawing();
    }

    rl.closeWindow();
}
