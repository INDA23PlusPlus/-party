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
const Invariables = @import("Invariables.zig");

const minigames_list = @import("minigames/list.zig").list;
const config = @import("config");
const starting_minigame_id = blk: {
    for (minigames_list, 0..minigames_list.len) |mg, i| {
        if (std.mem.eql(u8, mg.name, config.minigame)) {
            break :blk i;
        }
    }

    break :blk 0;
};

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

pub fn main() !void {
    // const launch_options = try LaunchOptions.parse();

    var window = win.Window.init(960, 540);
    defer window.deinit();

    var static_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const static_allocator = static_arena.allocator();
    defer static_arena.deinit();

    var frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const frame_allocator = frame_arena.allocator();
    defer frame_arena.deinit();

    var assets = AssetManager.init(static_allocator);
    defer assets.deinit();

    var shared_simulation = simulation.SharedSimulation{ .rw_lock = .{}, .sim = .{} };
    shared_simulation.sim.meta.minigame_id = starting_minigame_id; // TODO: Maybe sim.init() is a better place. Just add a new arg.

    var shared_input_timeline = InputTimeline{};

    var controllers = Controller.DefaultControllers;
    controllers[0].input_index = 0; // TODO: This is temporary.
    controllers[1].input_index = 1;

    // Networking
    // if (launch_options.start_as_role == .client) {
    //     try networking.startClient(&shared_simulation);
    // } else {
    //     try networking.startServer(&shared_simulation);
    // }

    const invariables = Invariables{
        .minigames_list = &minigames_list,
        .arena = frame_allocator,
    };

    try simulation.init(&shared_simulation.sim, invariables);

    var benchmarker = try @import("Benchmarker.zig").init("Simulation");

    // Game loop
    while (window.running) {
        // Make sure the main thread controls the world!
        shared_simulation.rw_lock.lock();

        // Fetch input.
        shared_input_timeline.rw_lock.lock();
        const tick = shared_simulation.sim.meta.ticks_elapsed;
        const frame_input: input.InputState = shared_input_timeline.localUpdate(&controllers, tick).*;
        shared_input_timeline.rw_lock.unlock();

        // All code that controls how objects behave over time in our game
        // should be placed inside of the simulate procedure as the simulate procedure
        // is called in other places. Not doing so will lead to inconsistencies.
        benchmarker.start();
        try simulation.simulate(&shared_simulation.sim, &frame_input, invariables);
        _ = static_arena.reset(.retain_capacity);
        benchmarker.stop();
        if (benchmarker.laps % 360 == 0) {
            try benchmarker.write();
            benchmarker.reset();
        }

        // Begin rendering.
        window.update();
        rl.beginDrawing();
        rl.clearBackground(BC_COLOR);
        render.update(&shared_simulation.sim.world, &assets, &window);

        // Stop rendering.
        rl.endDrawing();

        // Give the networking threads a chance to manipulate the world.
        shared_simulation.rw_lock.unlock();
    }
}
