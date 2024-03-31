const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const render = @import("../render.zig");
const assets_manager = @import("../assets_manager.zig");

const Self = @This();

// assets need to be loaded
const assets = [_][]const u8{
    "assets/test.png",
};

pub fn Game(self: *Self) root.Game {
    return .{
        .ptr = self,
        .initFn = init,
        .updateFn = update,
        .assets_paths = &assets,
        .assets_enum = assets_manager.AssetsEnum(&assets),
    };
}

fn update(ptr: *anyopaque, world: *ecs.World) ?u32 {
    const self: *Self = @ptrCast(@alignCast(ptr));
    _ = self;

    var query = world.query(&.{ ecs.Position, render.TextureComponent }, &.{});
    _ = query.next();
    const pos = try query.get(ecs.Position);
    pos.x += 1;
    pos.y += 1;

    rl.drawText("++party! :D", 8, 8, 96, rl.Color.blue);

    return null;
}

fn init(ptr: *anyopaque, world: *ecs.World) void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    _ = self;

    _ = try world.build(.{
        ecs.Position{
            .x = 0,
            .y = 0,
        },
        render.TextureComponent{
            .texture_hash = render.hash_texture("assets/test.png"),
            .tint = rl.Color.white,
            .scale = 1.0,
            .rotation = 0.0,
        },
    });
}
