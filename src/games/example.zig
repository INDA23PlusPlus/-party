const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const render = @import("../render.zig");
const assets_manager = @import("../assets_manager.zig");
const input = @import("../input.zig");

const Self = @This();

pub fn Game(self: *Self) root.Game {
    return .{
        .ptr = self,
        .initFn = initFn,
        .updateFn = update,
    };
}

var frame_arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var frame_allocator: *std.mem.Allocator = &frame_arena.allocator();
var test_entity: ecs.Entity = undefined;

fn initFn(ptr: *anyopaque, world: *ecs.World) void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    _ = self;

    test_entity = world.spawnWith(.{
        ecs.Position{
            .x = -100,
            .y = -100,
        },
        render.TextureComponent{
            .texture_hash = assets_manager.pathHash("assets/test.png"),
            .tint = rl.Color.white,
            .scale = 1.0,
            .rotation = 0.0,
        },
    }) catch @panic("failed to spawn test entity");

    // self.frame_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator).allocator();

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

fn update(ptr: *anyopaque, world: *ecs.World) ?u32 {
    const self: *Self = @ptrCast(@alignCast(ptr));

    // example of using a frame allocator
    defer _ = frame_arena.reset(std.heap.ArenaAllocator.ResetMode.retain_capacity);

    const pos = world.inspect(test_entity, ecs.Position) catch return 0;
    pos.x += 1;
    pos.y += 1;

    for (0..input.MAX_CONTROLLERS) |id| {
        var color = playerColors[id];
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

    if (win) {
        self.frame_arena.deinit();
        return 0;
    }

    return null;
}
