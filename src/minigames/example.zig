const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const render = @import("../render.zig");
const AssetManager = @import("../AssetManager.zig");
const input = @import("../input.zig");

//var frame_arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//var frame_allocator: *std.mem.Allocator = &frame_arena.allocator();

pub fn init(sim: *simulation.Simulation) !void {
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .vec = .{ 0, 0 } },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/kattis.png"),
            .tint = rl.Color.white,
        },
        ecs.component.Ctl{ .id = 0 },
    });
}

const win: bool = false;

const playerColors: [8]rl.Color = .{
    rl.Color.red,
    rl.Color.green,
    rl.Color.blue,
    rl.Color.yellow,
    rl.Color.orange,
    rl.Color.purple,
    rl.Color.pink,
    rl.Color.lime,
};

pub fn update(sim: *simulation.Simulation) !void {
    // example of using a frame allocator
    //defer _ = frame_arena.reset(std.heap.ArenaAllocator.ResetMode.retain_capacity);

    // Move all player controllers
    var controllable = sim.world.query(&.{ ecs.component.Pos, ecs.component.Ctl }, &.{});
    while (controllable.next()) |_| {
        const position = try controllable.get(ecs.component.Pos);
        const controller = try controllable.get(ecs.component.Ctl);
        const state = input.get(controller.id);
        if (state.isConnected) {
            position.vec[0] += 5 * state.horizontal();
            position.vec[1] += 5 * state.vertical();
        }
    }

    // Draw debug text (should not be here)
    rl.drawText("++party! :D", 8, 8, 96, rl.Color.blue);
}
