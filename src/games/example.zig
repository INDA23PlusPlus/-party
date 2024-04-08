const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const render = @import("../render.zig");
const assets_manager = @import("../assets_manager.zig");
const linear = @import("../ecs/linear.zig");
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
        ecs.Position{},
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

var point_1 = linear.V(16, 16).init(100, 500);
var point_2 = linear.V(16, 16).init(500, 100);
var up = false;
var left = false;

fn update(ptr: *anyopaque, world: *ecs.World) ?u32 {
    const self: *Self = @ptrCast(@alignCast(ptr));

    // example of using a frame allocator
    defer _ = frame_arena.reset(std.heap.ArenaAllocator.ResetMode.retain_capacity);

    const pos = world.inspect(test_entity, ecs.Position) catch return 0;
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

    if (win) {
        self.frame_arena.deinit();
        return 0;
    }

    return null;
}
