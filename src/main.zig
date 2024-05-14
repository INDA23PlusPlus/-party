const std = @import("std");
const rl = @import("raylib");

const win = @import("window.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const ecs = @import("ecs/ecs.zig");
const networking = @import("networking.zig");
const linear = @import("math/linear.zig");
const fixed = @import("math/fixed.zig");

const SimulationCache = @import("SimulationCache.zig");
const AssetManager = @import("AssetManager.zig");
const Controller = @import("Controller.zig");
const InputConsolidation = @import("InputConsolidation.zig");
const Invariables = @import("Invariables.zig");
const NetworkingQueue = @import("NetworkingQueue.zig");

const minigames_list = @import("minigames/list.zig").list;


/// How many resimulation steps can be performed each graphical frame.
/// This is used for catching up to the server elapsed_tick.
pub const max_simulations_per_frame = 512;

fn findMinigameID(preferred_minigame: []const u8) u32 {
    for (minigames_list, 0..) |mg, i| {
        if (std.mem.eql(u8, mg.name, preferred_minigame)) {
            return @truncate(i);
        }
    }

    std.debug.print("here is a list of possible minigames:\n", .{});
    for (minigames_list) |minigame| {
        std.debug.print("\t{s}\n", .{minigame.name});
    }
    std.debug.panic("unknown minigame: {s}", .{preferred_minigame});
}

// Settings
// TODO: move to settings file
const BC_COLOR = rl.Color.white;

const StartNetRole = enum {
    client,
    server,
    local,
};

const LaunchErrors = error{UnknownArg};

const LaunchOptions = struct {
    start_as_role: StartNetRole = StartNetRole.local,
    force_wasd: bool = false,
    force_ijkl: bool = false,
    force_minigame: u32 = 1,
    fn parse() !LaunchOptions {
        var result = LaunchOptions{};
        var mem: [1024]u8 = undefined;
        var alloc = std.heap.FixedBufferAllocator.init(&mem);
        const allocator = alloc.allocator();
        var args = try std.process.argsWithAllocator(allocator);
        defer args.deinit();

        // Skip the filename.
        _ = args.next();

        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "server")) {
                result.start_as_role = .server;
            } else if (std.mem.eql(u8, arg, "client")) {
                result.start_as_role = .client;
            } else if (std.mem.eql(u8, arg, "local")) {
                result.start_as_role = .local;
            } else if (std.mem.eql(u8, arg, "--wasd")) {
                result.force_wasd = true;
            } else if (std.mem.eql(u8, arg, "--ijkl")) {
                result.force_ijkl = true;
            } else if (std.mem.eql(u8, arg, "--minigame")) {
                result.force_minigame = findMinigameID(args.next() orelse "");
                std.debug.print("will launch minigame {d}\n", .{result.force_minigame});
            } else {
                std.debug.print("unknown argument: {s}\n", .{arg});
                return error.UnknownArg;
            }
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

    var simulation_cache = SimulationCache{};
    simulation_cache.start_state.meta.preferred_minigame_id = launch_options.force_minigame;
    simulation_cache.reset();

    var input_consolidation = try InputConsolidation.init(std.heap.page_allocator);

    var controllers = Controller.DefaultControllers;

    var main_thread_queue = NetworkingQueue{};
    var net_thread_queue = NetworkingQueue{};

    // Force WASD or IJKL for games that do not support hot-joining.
    if (launch_options.force_wasd or launch_options.force_ijkl) {
        try input_consolidation.extendTimeline(std.heap.page_allocator, 1);
    }
    if (launch_options.force_wasd) {
        _ = input_consolidation.forceAutoAssign(1, &controllers, 0);
    }
    if (launch_options.force_ijkl) {
        _ = input_consolidation.forceAutoAssign(1, &controllers, 1);
    }

    // Networking
    if (launch_options.start_as_role == .client) {
        std.debug.print("starting client thread\n", .{});
        try networking.startClient(&net_thread_queue);
    } else if (launch_options.start_as_role == .server) {
        std.debug.print("starting server thread\n", .{});
        try networking.startServer(&net_thread_queue);
    } else {
        std.debug.print("warning: multiplayer is disabled\n", .{});
    }

    if (launch_options.start_as_role != .local and launch_options.force_minigame != 1) {
        // TODO: To solve this, we should synchronize this info to all players such that we retain determinism.
        std.debug.print("warning: using --minigame and multiplayer is currently unsafe\n", .{});
    }

    const invariables = Invariables{
        .minigames_list = &minigames_list,
        .arena = frame_allocator,
    };

    // Used by networking code.
    var rewind_to_tick: u64 = std.math.maxInt(u64);
    var known_server_tick: u64 = 0;

    // var benchmarker = try @import("Benchmarker.zig").init("Simulation");

    // TODO: Perhaps a delay should be added to that (to non-local mode)
    // TODO: the networking thread has time to receive some updates?
    // TOOD: Or maybe something smarter like waiting for the first packet.

    // Game loop
    while (window.running) {
        // Fetch input.
        const tick = simulation_cache.head_tick_elapsed;

        // Make sure that the timeline extends far enough for the input polling to work.
        try input_consolidation.extendTimeline(std.heap.page_allocator, tick + 1);

        // TODO: Move to before polling local inputs.
        // Ingest the updates.
        for (main_thread_queue.incoming_data[0..main_thread_queue.incoming_data_count]) |change| {
            known_server_tick = @max(change.tick, known_server_tick);
            if (try input_consolidation.remoteUpdate(std.heap.page_allocator, change.player, change.data, change.tick)) {
                std.debug.assert(change.tick != 0);
                rewind_to_tick = @min(change.tick -| 1, rewind_to_tick);
            }
        }
        main_thread_queue.incoming_data_count = 0;

        // We want to know how many controllers are active locally in order to know if
        // all of their states can be sent over to the networking thread later on.
        const controllers_active = input_consolidation.autoAssign(&controllers, tick + 1);

        if (main_thread_queue.outgoing_data_count + controllers_active <= main_thread_queue.outgoing_data.len) {
            // We can only get local input, if we have the ability to send it. If we can't send it, we
            // mustn't accept local input as that could cause desynchs.
            try input_consolidation.localUpdate(&controllers, tick + 1);

            for (controllers) |controller| {
                if (!controller.isAssigned()) {
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

        if (launch_options.start_as_role == .local) {
            // Make sure we can scream into the void as much as we wish.
            main_thread_queue.outgoing_data_count = 0;
        } else {
            main_thread_queue.interchange(&net_thread_queue);
        }

        if (rewind_to_tick < simulation_cache.head_tick_elapsed) {
            //std.debug.print("rewind to {d}\n", .{rewind_to_tick});
            simulation_cache.rewind(rewind_to_tick);

            // The rewind is done. Reset it so that next tick
            // doesn't also rewind.
            rewind_to_tick = std.math.maxInt(u64);
        }

        if (rl.isKeyPressed(rl.KeyboardKey.key_r)) {
            std.debug.print("debug reset activated\n", .{});
            simulation_cache.rewind(0);
        }

        //if (simulation_cache.head_tick_elapsed == 300 + 1) {
        //    const file = std.io.getStdErr();
        //    const writer = file.writer();
        //    std.time.sleep(std.time.ns_per_s * 1);
        //    try input_consolidation.dumpInputs(writer);
        //}

        // benchmarker.start();

        for(0..max_simulations_per_frame) |_| {
            // All code that controls how objects behave over time in our game
            // should be placed inside of the simulate procedure as the simulate procedure
            // is called in other places. Not doing so will lead to inconsistencies.
            if (simulation_cache.head_tick_elapsed < input_consolidation.buttons.items.len) {
                const timeline_to_tick = input.Timeline{
                    .buttons = input_consolidation.buttons.items[0..simulation_cache.head_tick_elapsed + 1]
                };
                try simulation_cache.simulate(timeline_to_tick, invariables);
            }
            _ = static_arena.reset(.retain_capacity);

            if (simulation_cache.head_tick_elapsed >= known_server_tick) {
                // We have caught up. No need to do extra simulation steps now.
                break;
            }
        }

        // benchmarker.stop();
        // if (benchmarker.laps % 360 == 0) {
        //     try benchmarker.write();
        //     benchmarker.reset();
        // }

        // Begin rendering.
        window.update();
        rl.beginDrawing();
        rl.clearBackground(BC_COLOR);
        render.update(&simulation_cache.latest().world, &assets, &window);

        // Stop rendering.
        rl.endDrawing();
    }
}
