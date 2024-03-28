const std = @import("std");
const rl = @import("raylib");
const win = @import("window.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const ecs = @import("ecs/ecs.zig");
const linear = @import("ecs/linear.zig");
const time = @import("time.zig");

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

    var point_1 = linear.V(16, 16).init(100, 500);
    var point_2 = linear.V(16, 16).init(500, 100);
    var up = false;
    var left = false;

    // Game loop
    while (window.running) {
        defer _ = frame_arena.reset(std.heap.ArenaAllocator.ResetMode.retain_capacity);
        _ = frame_allocator;

        // Updates game systems
        time.update();
        input.preUpdate();
        window.update();
        // const res = physics.update()

        rl.beginDrawing();
        // Render -----------------------------

        // current_game.update(res);

        const pos = try world.inspect(thing, ecs.Position);
        pos.x += 1;
        pos.y += 1;

        if (left) {
            point_1.x = point_1.x.sub(comptime point_1.F.init(3, 2));
        } else {
            point_1.x = point_1.x.add(comptime point_1.F.init(3, 2));
        }

        if (up) {
            point_2.y = point_2.y.sub(1);
        } else {
            point_2.y = point_2.y.add(1);
        }

        if (point_1.x.toInt() > 960) left = true;
        if (point_1.x.toInt() <= 0) left = false;
        if (point_2.y.toInt() > 540) up = true;
        if (point_2.y.toInt() <= 0) up = false;

        var textColor: rl.Color = rl.Color.blue;
        if (input.A.down() and input.B.down()) {
            textColor = rl.Color.pink;
        } else if (input.A.down()) {
            textColor = rl.Color.green;
        } else if (input.B.down()) {
            textColor = rl.Color.red;
        }
        rl.drawText("++party! :D", 8, 8, 96, textColor);

        rl.drawLine(point_1.x.toInt(), point_1.y.toInt(), point_2.x.toInt(), point_2.y.toInt(), rl.Color.black);

        // std.debug.print("\ndpad: (dx:{} dy:{})\n", .{ input.DPad.dx(), input.DPad.dy() });

        // Stop Render -----------------------
        render_system.update();
        rl.endDrawing();

        input.postUpdate();
    }
}
