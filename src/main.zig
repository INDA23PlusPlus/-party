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
const Controller = @import("Controller.zig");
const InputConsolidation = @import("InputConsolidation.zig");
const Invariables = @import("Invariables.zig");
const NetworkingQueue = @import("NetworkingQueue.zig");

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
    const launch_options = try LaunchOptions.parse();

    var window = win.Window.init(960, 540); // 960, 540
    defer window.deinit();

    var static_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const static_allocator = static_arena.allocator();
    defer static_arena.deinit();

    var frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const frame_allocator = frame_arena.allocator();
    defer frame_arena.deinit();

    var assets = AssetManager.init(static_allocator);
    defer assets.deinit();

    var sim = simulation.Simulation{};
    sim.meta.minigame_id = starting_minigame_id; // TODO: Maybe sim.init() is a better place. Just add a new arg.

    var input_consolidation = try InputConsolidation.init(std.heap.page_allocator);
    var input_frames_sent: u64 = 0;

    var controllers = Controller.DefaultControllers;
    controllers[0].input_index = 0;
    controllers[1].input_index = 1;

    var main_thread_queue = NetworkingQueue{};
    var net_thread_queue = NetworkingQueue{};

    // Networking
    if (launch_options.start_as_role == .client) {
        try networking.startClient(&net_thread_queue);
    } else {
        try networking.startServer(&net_thread_queue);
    }

    const invariables = Invariables{
        .minigames_list = &minigames_list,
        .arena = frame_allocator,
    };

    try simulation.init(&sim, invariables);

    // var benchmarker = try @import("Benchmarker.zig").init("Simulation");

    // Game loop
    while (window.running) {

        // Fetch input.
        const tick = sim.meta.ticks_elapsed;
        const current_input_timeline = try input_consolidation.localUpdate(std.heap.page_allocator, &controllers, tick);

        // Add the inputs.
        // TODO: Write this code.

        for (input_frames_sent..input_consolidation.buttons.items.len) |tick_number| {
            const all_buttons = input_consolidation.buttons.items[tick_number];
            const local = input_consolidation.local.items[tick_number];
            for (all_buttons, 0..) |buttons, i| {
                if (main_thread_queue.outgoing_data_len >= main_thread_queue.outgoing_data.len) {
                    continue;
                }
                if (local.isSet(i)) {
                    main_thread_queue.outgoing_data[main_thread_queue.outgoing_data_len] = .{
                        .data = buttons,
                        .tick = tick_number,
                        .player = @truncate(i),
                    };
                    main_thread_queue.outgoing_data_len += 1;
                }
            }
        }
        input_frames_sent = input_consolidation.buttons.items.len;

        main_thread_queue.interchange(&net_thread_queue);

        // Ingest the updates.
        for (main_thread_queue.incoming_data[0..main_thread_queue.incoming_data_len]) |change| {
            _ = try input_consolidation.remoteUpdate(std.heap.page_allocator, change.player, change.data, change.tick);
        }
        main_thread_queue.incoming_data_len = 0;

        // All code that controls how objects behave over time in our game
        // should be placed inside of the simulate procedure as the simulate procedure
        // is called in other places. Not doing so will lead to inconsistencies.
        // benchmarker.start();
        try simulation.simulate(&sim, current_input_timeline, invariables);
        _ = static_arena.reset(.retain_capacity);
        // benchmarker.stop();
        // if (benchmarker.laps % 360 == 0) {
        //     try benchmarker.write();
        //     benchmarker.reset();
        // }

        // Begin rendering.
        window.update();
        rl.beginDrawing();
        rl.clearBackground(BC_COLOR);
        render.update(&sim.world, &assets, &window);

        // Stop rendering.
        rl.endDrawing();
    }
}
