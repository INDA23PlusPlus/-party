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
    local,
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
        } else if (std.mem.eql(u8, role, "local")) {
            result.start_as_role = .local;
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

    var controllers = Controller.DefaultControllers;

    var main_thread_queue = NetworkingQueue{};
    var net_thread_queue = NetworkingQueue{};

    // Networking
    if (launch_options.start_as_role == .client) {
        std.debug.print("starting server thread\n", .{});
        try networking.startClient(&net_thread_queue);
    } else if (launch_options.start_as_role == .server) {
        std.debug.print("starting client thread\n", .{});
        try networking.startServer(&net_thread_queue);
    } else {
        std.debug.print("warning: multiplayer is disabled\n", .{});
    }

    const invariables = Invariables{
        .minigames_list = &minigames_list,
        .arena = frame_allocator,
    };

    try simulation.start(&sim, invariables);

    // var benchmarker = try @import("Benchmarker.zig").init("Simulation");

    // Game loop
    while (window.running) {
        // Fetch input.
        const tick = sim.meta.ticks_elapsed;

        const controllers_active = Controller.autoAssign(&controllers);

        if (main_thread_queue.outgoing_data_count + controllers_active <= main_thread_queue.outgoing_data.len) {
            // We can only get local input, if we have the ability to send it. If we can't send it, we 
            // mustn't accept local input as that could cause desynchs.
            _ = try input_consolidation.localUpdate(std.heap.page_allocator, &controllers, tick);

            for(controllers) |controller| {
                if (!controller.is_assigned()) {
                    continue;
                }
                const player_index = controller.input_index;
                const data = input_consolidation.buttons.items[tick][player_index];

                main_thread_queue.outgoing_data[main_thread_queue.outgoing_data_count] = .{
                    .tick = tick,
                    .data = data,
                    .player = @truncate(player_index),
                };
                main_thread_queue.outgoing_data_count += 1;
            }
        } else {
            std.debug.print("unable to send further inputs as too many have been sent without answer\n", .{});
        }

        const current_input_timeline = input.Timeline { .buttons = input_consolidation.buttons.items[0..input_consolidation.buttons.items.len] };

        //if (tick == 1000) {
        //    const file = std.io.getStdErr();
        //    const writer = file.writer();
        //    try input_consolidation.dumpInputs(writer);
        //    std.time.sleep(std.time.ns_per_s * 2);
        //    @panic("over");
        //}

        if (launch_options.start_as_role == .local) {
            // Make sure we can scream into the void as much as we wish.
            main_thread_queue.outgoing_data_count = 0;
        } else {
            main_thread_queue.interchange(&net_thread_queue);
        }

        // Ingest the updates.
        for (main_thread_queue.incoming_data[0..main_thread_queue.incoming_data_count]) |change| {
            //std.debug.print("ingesting update\n", .{});
            _ = try input_consolidation.remoteUpdate(std.heap.page_allocator, change.player, change.data, change.tick);
        }
        main_thread_queue.incoming_data_count = 0;

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
