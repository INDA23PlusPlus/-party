const std = @import("std");
const rl = @import("raylib");

const win = @import("window.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const playback = @import("playback.zig");
const ecs = @import("ecs/ecs.zig");
const networking = @import("networking.zig");
const linear = @import("math/linear.zig");
const fixed = @import("math/fixed.zig");

const SimulationCache = @import("SimulationCache.zig");
const AssetManager = @import("AssetManager.zig");
const AudioManager = @import("AudioManager.zig");
const Controller = @import("Controller.zig");
const InputMerger = @import("InputMerger.zig");
const Invariables = @import("Invariables.zig");
const NetworkingQueue = @import("NetworkingQueue.zig");

const minigames_list = @import("minigames/list.zig").list;

/// How many resimulation steps can be performed each graphical frame.
/// This is used for catching up to the server elapsed_tick.
pub const max_simulations_per_frame = 512;

/// We introduce an input delay on purpose such that there is a chance that the
/// input travels to the server in time to avoid resimulations.
/// A low value is very optimistic...
const useful_input_delay = 1;

/// The maximum number of frames that the client may be ahead of the known_server_tick before
/// the client will reset its newest_local_input_tick to prevent further resimulations into
/// the future.
const max_allowed_time_travel_to_future = 8;

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
    hostname: []const u8 = "127.0.0.1",
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
            } else if (std.mem.eql(u8, arg, "--hostname")) {
                result.hostname = args.next() orelse "";
            } else {
                std.debug.print("unknown argument: {s}\n", .{arg});
                return error.UnknownArg;
            }
        }

        return result;
    }
};

pub fn submitInputs(controllers: []Controller, input_merger: *InputMerger, input_tick: u64, main_thread_queue: *NetworkingQueue) void {
    for (controllers) |controller| {
        if (!controller.isAssigned()) {
            continue;
        }
        const player_index = controller.input_index;
        const data = input_merger.buttons.items[input_tick][player_index];

        main_thread_queue.outgoing_data[main_thread_queue.outgoing_data_count] = .{
            .tick = input_tick,
            .data = data,
            .player = @truncate(player_index),
            .is_owned = true, // Not really used right now.
        };
        main_thread_queue.outgoing_data_count += 1;
    }
}

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

    var audm = try AudioManager.init(static_allocator);
    defer audm.deinit();

    var simulation_cache = SimulationCache{};
    simulation_cache.start_state.meta.preferred_minigame_id = launch_options.force_minigame;
    simulation_cache.reset();

    var input_merger = try InputMerger.init(std.heap.page_allocator);

    var controllers = Controller.DefaultControllers;

    var main_thread_queue = NetworkingQueue{};
    var net_thread_queue = NetworkingQueue{};

    // Force WASD or IJKL for games that do not support hot-joining.
    if (launch_options.force_wasd or launch_options.force_ijkl) {
        try input_merger.extendTimeline(std.heap.page_allocator, 1);
    }
    if (launch_options.force_wasd) {
        _ = input_merger.forceAutoAssign(0, &controllers, 0);
    }
    if (launch_options.force_ijkl) {
        _ = input_merger.forceAutoAssign(0, &controllers, 1);
    }

    // If this is not done, then we desynch. Maybe there is a prettier solution
    // to forced input assignments. But this works, so too bad!
    // In other words, we make sure that other clients know about the forceAutoAssigns.
    // If no forceAutoAssign has happened, then all of the controllers will be unassigned at this stage.
    // So the call can't hurt anyone.
    submitInputs(&controllers, &input_merger, 1, &main_thread_queue);

    // Networking
    if (launch_options.start_as_role == .client) {
        std.debug.print("starting client thread\n", .{});
        if (std.mem.eql(u8, launch_options.hostname, "")) {
            @panic("missing hostname parameter");
        }
        try networking.startClient(&net_thread_queue, launch_options.hostname);
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
    var newest_local_input_tick: u64 = 0;

    // var benchmarker = try @import("Benchmarker.zig").init("Simulation");

    // TODO: Perhaps a delay should be added to that (to non-local mode)
    // TODO: the networking thread has time to receive some updates?
    // TOOD: Or maybe something smarter like waiting for the first packet.

    // Game loop
    while (window.running) {
        // Fetch input.
        const tick = simulation_cache.head_tick_elapsed;

        const input_tick_delayed = tick + 1 + useful_input_delay;

        // Make sure that the timeline extends far enough for the input polling to work.
        try input_merger.extendTimeline(std.heap.page_allocator, input_tick_delayed);

        // Ingest the updates.
        for (main_thread_queue.incoming_data[0..main_thread_queue.incoming_data_count]) |change| {
            known_server_tick = @max(change.tick, known_server_tick);

            //std.debug.print("setting remote {d} {d}\n", .{change.tick, change.player});
            if (try input_merger.remoteUpdate(std.heap.page_allocator, change.player, change.data, change.tick)) {
                std.debug.assert(change.tick != 0);
                rewind_to_tick = @min(change.tick -| 1, rewind_to_tick);
            }
        }
        main_thread_queue.incoming_data_count = 0;

        Controller.pollAll(&controllers, input_merger.buttons.items[input_tick_delayed - 1]);

        // We want to know how many controllers are active locally in order to know if
        // all of their states can be sent over to the networking thread later on.
        const controllers_active = input_merger.autoAssign(&controllers, input_tick_delayed - 1);

        if (main_thread_queue.outgoing_data_count + controllers_active <= main_thread_queue.outgoing_data.len) {
            // We can only get local input, if we have the ability to send it. If we can't send it, we
            // mustn't accept local input as that could cause desynchs.

            if (known_server_tick -| (useful_input_delay * 2) < input_tick_delayed) {
                // We only try to update the timeline if we are not too far back in the past.

                //std.debug.print("setting local {d}\n", .{input_tick_delayed});
                try input_merger.localUpdate(&controllers, input_tick_delayed);

                // Tell the networking thread about the changes we just made to the timeline.
                submitInputs(&controllers, &input_merger, input_tick_delayed, &main_thread_queue);

                newest_local_input_tick = @max(newest_local_input_tick, input_tick_delayed);
            } else {
                std.debug.print("too far back in the past to take input\n", .{});
            }
        } else {
            std.debug.print("unable to send further inputs as too many have been sent without answer\n", .{});
        }

        if (newest_local_input_tick > known_server_tick + max_allowed_time_travel_to_future) {
            // If we stray too far away from the known_server_tick, we reset
            // the variable such that resimulation doesn't take us too far
            // into the future.
            newest_local_input_tick = 0;
        }

        if (launch_options.start_as_role == .local) {
            // Make sure we can scream into the void as much as we wish.
            main_thread_queue.outgoing_data_count = 0;
        } else {
            // Make sure the server knows how far the local client has come.
            main_thread_queue.client_acknowledge_tick = known_server_tick;

            main_thread_queue.interchange(&net_thread_queue);
        }

        if (rewind_to_tick < simulation_cache.head_tick_elapsed) {
            //std.debug.print("rewind to {d}\n", .{rewind_to_tick});
            simulation_cache.rewind(rewind_to_tick);

            // The rewind is done. Reset it so that next tick
            // doesn't also rewind.
            rewind_to_tick = std.math.maxInt(u64);
        }

        const debug_key_down = rl.isKeyDown(rl.KeyboardKey.key_p);
        if (debug_key_down and rl.isKeyPressed(rl.KeyboardKey.key_one)) {
            std.debug.print("debug reset activated\n", .{});
            simulation_cache.rewind(0);
        }
        if (debug_key_down and rl.isKeyPressed(rl.KeyboardKey.key_two)) {
            const file = std.io.getStdErr();
            const writer = file.writer();
            try input_merger.dumpInputs((tick >> 9) << 9, writer);
        }

        // benchmarker.start();

        for (0..max_simulations_per_frame) |_| {
            // All code that controls how objects behave over time in our game
            // should be placed inside of the simulate procedure as the simulate procedure
            // is called in other places. Not doing so will lead to inconsistencies.
            if (simulation_cache.head_tick_elapsed < input_merger.buttons.items.len) {
                const timeline_to_tick = input.Timeline{ .buttons = input_merger.buttons.items[0 .. simulation_cache.head_tick_elapsed + 1] };
                try simulation_cache.simulate(timeline_to_tick, invariables);
            }
            _ = frame_arena.reset(.retain_capacity);

            const close_to_server = simulation_cache.head_tick_elapsed >= known_server_tick;
            const close_to_local = simulation_cache.head_tick_elapsed >= newest_local_input_tick -| (useful_input_delay + 1);

            if (close_to_server and close_to_local) {
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
        rl.clearBackground(rl.Color.white);
        render.update(&simulation_cache.latest().world, &assets, &window);

        // Stop rendering.
        rl.endDrawing();

        playback.update(&simulation_cache.latest().world, &audm);
    }
}
