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

fn update(ptr: *anyopaque, world: *ecs.World) ?u32 {
    const self: *Self = @ptrCast(@alignCast(ptr));

    // example of using a frame allocator
    defer _ = frame_arena.reset(std.heap.ArenaAllocator.ResetMode.retain_capacity);

    const pos = world.inspect(test_entity, ecs.Position) catch return 0;
    pos.x += 1;
    pos.y += 1;

    var textColor: rl.Color = rl.Color.blue;
    if (input.A.down() and input.B.down()) {
        textColor = rl.Color.pink;
    } else if (input.A.down()) {
        textColor = rl.Color.green;
    } else if (input.B.down()) {
        textColor = rl.Color.red;
    }
    rl.drawText("++party! :D", 8, 8, 96, textColor);

    if (win) {
        self.frame_arena.deinit();
        return 0;
    }

    return null;
}
