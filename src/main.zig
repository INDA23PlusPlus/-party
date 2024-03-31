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

// import games and create a instance of it
var example_game = @import("games/example.zig"){};

// create list of Game instances
const games = [_]Game{
    example_game.Game(),
};

// Settings
// TODO: move to settings file
const BC_COLOR = rl.Color.gray;

/// interface for a mini game look at games/example.zig for a reference implementation
pub const Game = struct {
    ptr: *anyopaque,

    /// returns list of file paths to load in the resource loader
    initFn: *const fn (ptr: *anyopaque, world: *ecs.World) void,
    // TODO: pass in collisions
    /// returns score if game is over
    updateFn: *const fn (ptr: *anyopaque, world: *ecs.World) ?u32,

    assets_paths: []const []const u8,

    pub fn init(self: *Game, world: *ecs.World) void {
        return self.initFn(self.ptr, world);
    }

    pub fn update(self: *Game, world: *ecs.World) void {
        self.updateFn(self.ptr, world);
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
    defer game_arena.deinit();
    const game_allocator = game_arena.allocator();

    var frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer frame_arena.deinit();
    const frame_allocator = frame_arena.allocator();

    var world_buffer: ecs.Buffer = undefined;
    var world = ecs.World.init(&world_buffer);

    // TODO: game selection
    var current_game = games[0];
    current_game.init(&world);
    defer current_game.deinit();

    var assets_manager_system = assets_manager.AssetsManager(&current_game).init(&game_allocator);
    defer assets_manager_system.deinit();

    var render_system = render.init(&world, BC_COLOR, &assets_manager_system);
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

    var point_1 = linear.V(16, 16).init(100, 500);
    var point_2 = linear.V(16, 16).init(500, 100);
    var up = false;
    var left = false;

    // Game loop
    while (window.running) {
        _ = frame_allocator;
        defer _ = frame_arena.reset(std.heap.ArenaAllocator.ResetMode.retain_capacity);

        // Updates game systems
        time.update();
        input.preUpdate();
        window.update();
        // const collisions = physics.update()

        rl.beginDrawing();
        // Render -----------------------------

        current_game.update(&world); // TODO: pass in collisions
        // current_game.update(res);

        const pos = try world.inspect(thing, ecs.Position);
        pos.x += 1;
        pos.y += 1;

        if (left) {
            point_1.x = point_1.x.sub(comptime point_1.F.init(3, 2));
        } else {
            point_1.x = point_1.x.add(comptime point_1.F.init(3, 2));
        }

        if (up) {
            point_2.y = point_2.y.sub(1);
        } else {
            point_2.y = point_2.y.add(1);
        }

        if (point_1.x.toInt() > 960) left = true;
        if (point_1.x.toInt() <= 0) left = false;
        if (point_2.y.toInt() > 540) up = true;
        if (point_2.y.toInt() <= 0) up = false;

        var textColor: rl.Color = rl.Color.blue;
        if (input.A.down() and input.B.down()) {
            textColor = rl.Color.pink;
        } else if (input.A.down()) {
            textColor = rl.Color.green;
        } else if (input.B.down()) {
            textColor = rl.Color.red;
        }
        rl.drawText("++party! :D", 8, 8, 96, textColor);

        rl.drawLine(point_1.x.toInt(), point_1.y.toInt(), point_2.x.toInt(), point_2.y.toInt(), rl.Color.black);

        // std.debug.print("\ndpad: (dx:{} dy:{})\n", .{ input.DPad.dx(), input.DPad.dy() });

        // Stop Render -----------------------
        render_system.update();
        rl.endDrawing();

        input.postUpdate();
    }
}
