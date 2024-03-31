const std = @import("std");
const rl = @import("raylib");
const win = @import("window.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const ecs = @import("ecs/ecs.zig");
const time = @import("time.zig");
const networking = @import("networking.zig");
const linear = @import("math/linear.zig");
const fixed = @import("math/fixed.zig");

// Settings
const BC_COLOR = rl.Color.gray;

const StartNetRole = enum {
    client,
    server,
};

const LaunchErrors = error{UnknownRole};

const LaunchOptions = struct {
    start_as_role: StartNetRole = StartNetRole.client,
    fn parse() !LaunchOptions {
        var result = LaunchOptions{};
        var mem: [1024]u8 = undefined;
        var alloc = std.heap.FixedBufferAllocator.init(&mem);
        const allocator = alloc.allocator();
        var args = try std.process.argsWithAllocator(allocator);
        defer args.deinit();

        // Skip the filename.
        _ = args.next();

        const role = args.next() orelse return error.UnknownRole;
        if (std.mem.eql(u8, role, "server")) {
            result.start_as_role = .server;
        } else if (std.mem.eql(u8, role, "client")) {
            result.start_as_role = .client;
        } else {
            return error.UnknownRole;
        }

        return result;
    }
};

inline fn initWindow(resolution: enum { FHD, HD, qHD, nHD }) win.Window {
    switch (resolution) {
        .FHD => return win.Window.init(1980, 1080),
        .HD => return win.Window.init(1280, 720),
        .qHD => return win.Window.init(960, 540),
        .nHD => return win.Window.init(640, 360),
    }
}

pub fn main() !void {
    const launch_options = try LaunchOptions.parse();
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

    // Networking
    if (launch_options.start_as_role == .client) {
        try networking.startClient();
    } else {
        try networking.startServer();
    }

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
        _ = frame_allocator;
        defer _ = frame_arena.reset(std.heap.ArenaAllocator.ResetMode.retain_capacity);

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

        rl.drawText("++party! :D", 8, 8, 96, rl.Color.blue);

        // Stop Render -----------------------
        render_system.update();
        rl.endDrawing();

        input.postUpdate();
    }
}
