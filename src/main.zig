const std = @import("std");
const rl = @import("raylib");

const win = @import("window.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const ecs = @import("ecs/ecs.zig");
const assets_manager = @import("assets_manager.zig");
const linear = @import("ecs/linear.zig");
const time = @import("time.zig");
const networking = @import("networking.zig");

// import games and init them
var example_game = @import("games/example.zig"){};

// create list of Game instances
var games = [_]Game{
    example_game.Game(),
};

// Settings
// TODO: move to settings file
const BC_COLOR = rl.Color.gray;

/// interface for a mini game look at games/example.zig for a reference implementation
pub const Game = struct {
    ptr: *anyopaque,

    initFn: *const fn (ptr: *anyopaque, world: *ecs.World) void,
    // TODO: pass in collisions
    /// returns score if game is over
    updateFn: *const fn (ptr: *anyopaque, world: *ecs.World) ?u32,

    pub fn init(self: *Game, world: *ecs.World) void {
        return self.initFn(self.ptr, world);
    }

    pub fn update(self: *Game, world: *ecs.World) ?u32 {
        return self.updateFn(self.ptr, world);
    }
};

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

    var assets_manager_system = assets_manager.init(game_allocator);
    defer assets_manager_system.deinit();

    // var game_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer game_arena.deinit();
    // const game_allocator = game_arena.allocator();

    var world_buffer: ecs.Buffer = undefined;
    var world = ecs.World.init(&world_buffer);

    // TODO: game selection
    var game_i: usize = 0;
    games[game_i].init(&world);

    // Networking
    if (launch_options.start_as_role == .client) {
        try networking.startClient();
    } else {
        try networking.startServer();
    }

    var result: ?u32 = null;

    // Game loop
    while (window.running) {
        rl.clearBackground(BC_COLOR);
        // Updates game systems
        time.update();
        input.preUpdate();
        window.update();
        // const collisions = physics.update()

        rl.beginDrawing();
        // Render -----------------------------

        result = games[game_i].update(&world); // TODO: pass in collisions
        // current_game.update(res);

        // Stop Render -----------------------
        render.update(&world, &assets_manager_system);
        rl.endDrawing();

        input.postUpdate();

        if (result) |_| {
            // deinit current game

            game_i += 1;

            if (game_i >= games.len) {
                break;
            }

            // init next game
            world_buffer = undefined;
            world = ecs.World.init(&world_buffer);
            games[game_i].init(&world);
        }
    }
}
