const std = @import("std");
const rl = @import("raylib");

const win = @import("window.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const ecs = @import("ecs/ecs.zig");
const networking = @import("networking.zig");
const linear = @import("math/linear.zig");
const fixed = @import("math/fixed.zig");
const simulation = @import("simulation.zig");
const minigames = @import("minigames/list.zig");

const AssetManager = @import("AssetManager.zig");
const Controller = @import("controller.zig");
const InputTimeline = @import("InputTimeline.zig");

// Settings
// TODO: move to settings file
const BC_COLOR = rl.Color.white;

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

    var shared_simulation = simulation.SharedSimulation{ .rw_lock = .{}, .sim = .{} };

    var shared_input_timeline = InputTimeline{};

    var controllers = Controller.DefaultControllers;
    controllers[0].input_index = 0; // TODO: This is temporary.
    controllers[1].input_index = 1;

    // Networking
    if (launch_options.start_as_role == .client) {
        try networking.startClient(&shared_simulation);
    } else {
        try networking.startServer(&shared_simulation);
    }

    try simulation.init(&shared_simulation.sim);

    var time: u64 = 0;
    var laps: u64 = 0;
    var out = std.io.getStdOut();
    var writer = out.writer();

    // Game loop
    while (window.running) {
        // Make sure the main thread controls the world!
        shared_simulation.rw_lock.lock();

        // Fetch input.
        shared_input_timeline.rw_lock.lock();
        const tick = shared_simulation.sim.meta.ticks_elapsed; // WILL ALWAYS BE ZERO
        const frame_input: input.InputState = shared_input_timeline.localUpdate(&controllers, tick).*;
        shared_input_timeline.rw_lock.unlock();

        // All code that controls how objects behave over time in our game
        // should be placed inside of the simulate procedure as the simulate procedure
        // is called in other places. Not doing so will lead to inconsistencies.
        var timer = try std.time.Timer.start();
        try simulation.simulate(&shared_simulation.sim, &frame_input, game_allocator);
        time += timer.lap();
        laps += 1;
        if (laps % 360 == 0) {
            const t: f64 = @floatFromInt(time);
            const l: f64 = @floatFromInt(laps);

            const ns_per_lap = t / l;
            const ms_per_lap = ns_per_lap / std.time.ns_per_ms;
            try writer.print("{d:>.4} ms/lap \n", .{ms_per_lap});

            const laps_per_ns = l / t;
            const laps_per_ms = laps_per_ns * std.time.ns_per_ms;
            try writer.print("{d:>.4} laps/ms \n", .{laps_per_ms});

            const frames_per_lap = ms_per_lap / 17.0;
            try writer.print("{d:>.4} frames/lap \n", .{frames_per_lap});

            const laps_per_frame = laps_per_ms * 17.0;

            try writer.print("{d:>.4} laps/frame \n", .{laps_per_frame});

            try writer.print("allocated bytes: {}", .{game_arena.queryCapacity()});
        }

        // Begin rendering.
        window.update();
        rl.beginDrawing();
        rl.clearBackground(BC_COLOR);
        render.update(&shared_simulation.sim.world, &assets);

        // Stop rendering.
        rl.endDrawing();

        // Give the networking threads a chance to manipulate the world.
        shared_simulation.rw_lock.unlock();
    }
}
