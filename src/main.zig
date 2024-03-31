const std = @import("std");
const rl = @import("raylib");

const win = @import("window.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const ecs = @import("ecs/ecs.zig");
const assets_manager = @import("assets_manager.zig");

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

pub fn main() !void {
    var window = win.Window.init(1920, 1080);
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

    // Game loop
    while (window.running) {
        defer _ = frame_arena.reset(std.heap.ArenaAllocator.ResetMode.retain_capacity);
        _ = frame_allocator;

        // Updates game systems
        input.update();
        window.update();
        // const collisions = physics.update()

        rl.beginDrawing();
        // Render -----------------------------

        current_game.update(&world); // TODO: pass in collisions

        // Stop Render -----------------------
        render_system.update();
        rl.endDrawing();
    }
}
