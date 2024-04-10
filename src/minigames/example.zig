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
        ecs.component.Pos{ .vec = @splat(-100) },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/test.png"),
        },
    });
}

const win: bool = false;

const playerColors: [input.MAX_CONTROLLERS]rl.Color = .{
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
    var pos_query = sim.world.query(&.{ecs.component.Pos}, &.{});
    while (pos_query.next()) |_| {
        const pos = try pos_query.get(ecs.component.Pos);

        // Temp
        // Note, inputs should not be handled like this.
        if (rl.isKeyDown(rl.KeyboardKey.key_a)) pos.vec[0] -= 5;
        if (rl.isKeyDown(rl.KeyboardKey.key_d)) pos.vec[0] += 5;
        if (rl.isKeyDown(rl.KeyboardKey.key_w)) pos.vec[1] -= 5;
        if (rl.isKeyDown(rl.KeyboardKey.key_s)) pos.vec[1] += 5;
    }

    for (0..input.MAX_CONTROLLERS) |id| {
        var color = playerColors[id];
        // TODO: Doing rendering code in the update() is not well advised. Preferrably the renderer should be able
        // to draw everything that we want it to. If not, then perhaps a render() callback could be added to the interface.
        if (input.controller(id) == null) {
            color = rl.colorAlpha(rl.colorBrightness(color, -0.5), 0.5);
        } else {
            if (input.controller(id).?.primary().down()) {
                color = rl.colorBrightness(color, 0.5);
            }
        }
        rl.drawText(rl.textFormat("Player %d", .{id}), 8, @intCast(128 + 32 * id), 32, color);
    }

    rl.drawText("++party! :D", 8, 8, 96, rl.Color.blue);
}
