const std = @import("std");
const rl = @import("raylib");
const win = @import("window.zig");
const input = @import("input.zig");
const render = @import("render.zig");

// Settings
const BC_COLOR = rl.Color.gray;

pub fn main() void {
    var window = win.Window.init(1920, 1080);
    defer window.deinit();

    var game_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer game_arena.deinit();
    const game_allocator = game_arena.allocator();

    var frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer frame_arena.deinit();
    const frame_allocator = frame_arena.allocator();

    var render_system = render.init(game_allocator, BC_COLOR);
    defer render_system.deinit();

    // Game loop
    while (window.running) {
        defer _ = frame_arena.reset(std.heap.ArenaAllocator.ResetMode.retain_capacity);
        _ = frame_allocator;

        // Updates game systems
        input.update();
        window.update();
        // physics.update()

        rl.beginDrawing();
        render_system.update();
        // Render -----------------------------

        rl.drawText("++party! :D", 8, 8, 96, rl.Color.blue);

        // Stop Render -----------------------
        rl.endDrawing();
    }
}
