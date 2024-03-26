const std = @import("std");
const rl = @import("raylib");
const win = @import("window.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const ecs = @import("ecs/ecs.zig");

// Settings
const BC_COLOR = rl.Color.gray;

pub fn main() !void {
    var window = win.Window.init(1920, 1080);
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
    _ = try world.build(.{
        ecs.Position{
            .x = 0,
            .y = 0,
        },
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

        var query = world.query(&.{ ecs.Position, render.TextureComponent }, &.{});
        _ = query.next();
        const pos = try query.get(ecs.Position);
        pos.x += 1;
        pos.y += 1;

        rl.drawText("++party! :D", 8, 8, 96, rl.Color.blue);

        // Stop Render -----------------------
        render_system.update();
        rl.endDrawing();
    }
}
