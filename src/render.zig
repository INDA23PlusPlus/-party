const rl = @import("raylib");
const std = @import("std");
const ecs = @import("ecs/world.zig");
const assets_manager = @import("assets_manager.zig");

/// ecs component that will render a texture
pub const TextureComponent = struct {
    texture_hash: u64,
    tint: rl.Color, // TODO: does this work for serialization?
    rotation: f32, // TODO: fixed point
    scale: f32, // TODO: fixed point
};

pub fn update(world: *ecs.World, am: *assets_manager) void {
    var query = world.query(&.{ ecs.Position, TextureComponent }, &.{});

    while (query.next()) |_| {
        const pos_component = query.get(ecs.Position) catch unreachable;
        const c = query.get(TextureComponent) catch unreachable;

        const pos = rl.Vector2{ .x = @floatFromInt(pos_component.x), .y = @floatFromInt(pos_component.y) };

        // TODO: error handling
        const texture = am.hashmap.get(c.texture_hash) orelse @panic("Texture not found");

        rl.drawTextureEx(texture, pos, c.rotation, c.scale, c.tint);
    }
}
