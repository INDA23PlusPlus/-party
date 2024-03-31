const rl = @import("raylib");
const std = @import("std");
const ecs = @import("ecs/ecs.zig");
const assets_manager = @import("assets_manager.zig");
const root = @import("root");

// TODO: red this from a config file
bc_color: rl.Color,
world: *ecs.World,
assets_manager: assets_manager.AssetsManager,

const Self = @This();

pub fn TextureComponent(game: root.Game, tint: rl.Color, rotation: f32, scale: f32) type {
    return .{
        .asset_enum = game.assets_enum,
        .tint = tint,
        .rotation = rotation,
        .scale = scale,
    };
}

pub fn init(world: *ecs.World, background_color: rl.Color, manager: *assets_manager.AssetManager) @This() {
    return .{
        .world = world,
        .bc_color = background_color,
        .assets_manager = manager,
    };
}

pub fn update(self: *Self) void {
    rl.clearBackground(self.bc_color);

    var query = self.world.query(&.{ ecs.Position, assets_manager.TextureComponent }, &.{});
    while (query.next()) |_| {
        const pos_component = query.get(ecs.Position) catch unreachable;
        const c = query.get(TextureComponent) catch unreachable;

        const pos = rl.Vector2{ .x = @floatFromInt(pos_component.x), .y = @floatFromInt(pos_component.y) };
        const texture = self.assets_manager.hashmap.get(c.texture_hash) orelse @panic("Texture not found");

        rl.drawTextureEx(texture, pos, c.scale, c.rotation, c.tint);
    }
}
