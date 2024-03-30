const std = @import("std");
const rl = @import("raylib");
const win = @import("window.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const networking = @import("networking.zig");

// Settings
const BC_COLOR = rl.Color.gray;

const StartNetRole = enum {
    client,
    server,
};

const LaunchErrors = error {
    UnknownRole
};

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

    var window = win.Window.init(1920, 1080);
    defer window.deinit();

    var game_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer game_arena.deinit();
    const game_allocator = game_arena.allocator();

    // init systems and game
    var render_system = render.init(game_allocator, BC_COLOR);
    defer render_system.deinit();

    var frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer frame_arena.deinit();
    const frame_allocator = frame_arena.allocator();
    // var current_game = game.init(game_allocator);
    // defer current_game.deinit();


    // networking
    if (launch_options.start_as_role == .client) {
        try networking.startClient();
    } else {
        try networking.startServer();
    }

    // Game loop
    while (window.running) {
        _ = frame_allocator;
        defer _ = frame_arena.reset(std.heap.ArenaAllocator.ResetMode.retain_capacity);

        // Updates game systems
        input.update();
        window.update();
        // const res = physics.update()

        rl.beginDrawing();
        // Render -----------------------------

        // current_game.update(res);

        rl.drawText("++party! :D", 8, 8, 96, rl.Color.blue);

        // Stop Render -----------------------
        render_system.update();
        rl.endDrawing();
    }
}
