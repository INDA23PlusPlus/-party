const std = @import("std");
const rl = @import("raylib");
const win = @import("window.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const ecs = @import("ecs/ecs.zig");

// Settings
const BC_COLOR = rl.Color.gray;

inline fn initWindow(resolution: enum { FHD, HD, qHD, nHD }) win.Window {
    switch (resolution) {
        .FHD => return win.Window.init(1980, 1080),
        .HD => return win.Window.init(1280, 720),
        .qHD => return win.Window.init(960, 540),
        .nHD => return win.Window.init(640, 360),
    }
}

pub fn main() !void {
    var window = initWindow(.qHD);
    defer window.deinit();

    var game_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer game_arena.deinit();
    const game_allocator = game_arena.allocator();

    var frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer frame_arena.deinit();
    const frame_allocator = frame_arena.allocator();

    var world_buffer: ecs.Buffer = undefined;
    var world = ecs.World.init(&world_buffer);

    var render_system = render.init(game_allocator, &world, BC_COLOR);
    defer render_system.deinit();

    // var current_game = game.init(game_allocator);
    // defer current_game.deinit();

    // example
    const thing = try world.spawnWith(.{
        ecs.Position{},
        render.TextureComponent{
            .texture_hash = try render_system.load_texture("assets/test.png"),
            .tint = rl.Color.white,
            .scale = 1.0,
            .rotation = 0.0,
        },
    });

    // Game loop
    while (window.running) {
        defer _ = frame_arena.reset(std.heap.ArenaAllocator.ResetMode.retain_capacity);
        _ = frame_allocator;

        // Updates game systems
        input.update();
        window.update();
        // const res = physics.update()

        rl.beginDrawing();
        // Render -----------------------------

        // current_game.update(res);

        const pos = try world.inspect(thing, ecs.Position);
        pos.x += 1;
        pos.y += 1;

        rl.drawText("++party! :D", 8, 8, 96, rl.Color.blue);

        // Stop Render -----------------------
        render_system.update();
        rl.endDrawing();
    }
}
