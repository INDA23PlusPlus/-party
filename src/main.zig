const std = @import("std");
const rl = @import("raylib");

const win = @import("window.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const ecs = @import("ecs/ecs.zig");
const AssetManager = @import("AssetManager.zig");
const time = @import("time.zig");
const networking = @import("networking.zig");
const linear = @import("math/linear.zig");
const fixed = @import("math/fixed.zig");
const simulation = @import("simulation.zig");
const minigames = @import("minigames/list.zig");

// Settings
// TODO: move to settings file
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
    const game_allocator = game_arena.allocator();
    defer game_arena.deinit();

    var assets = AssetManager.init(game_allocator);
    defer assets.deinit();

    var shared_world = simulation.SharedSimulation{ .rw_lock = .{}, .sim = .{} };

    // Networking
    if (launch_options.start_as_role == .client) {
        try networking.startClient(&shared_world);
    } else {
        try networking.startServer(&shared_world);
    }

    // Game loop
    while (window.running) {
        // Make sure the main thread controls the world!
        shared_world.rw_lock.lock();

        // Updates game systems
        time.update(); // TODO: Move into world.
        input.poll(); // TODO: Make the input module thread-safe such that the networking threads may access it as well.

        // All code that controls how objects behave over time in our game
        // should be placed inside of the simulate procedure as the simulate procedure
        // is called in other places. Not doing so will lead to inconsistencies.
        try simulation.simulate(&minigames.list, &shared_world.sim);

        // Render -----------------------------
        window.update();
        rl.beginDrawing();
        rl.clearBackground(BC_COLOR);
        render.update(&shared_world.sim.world, &assets);

        // Stop Render -----------------------
        rl.endDrawing();

        input.post();

        // Give the networking threads a chance to manipulate the world.
        shared_world.rw_lock.unlock();
    }
}
