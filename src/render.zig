const rl = @import("raylib");
const std = @import("std");
const ecs = @import("ecs/ecs.zig");
const assets_manager = @import("assets_manager.zig");

pub fn update(world: *ecs.world.World, am: *assets_manager) void {
    var query = world.query(&.{ ecs.component.Pos, ecs.component.Tex }, &.{});

    while (query.next()) |_| {
        const pos_component = query.get(ecs.component.Pos) catch unreachable;
        const c = query.get(ecs.component.Tex) catch unreachable;

        const pos = rl.Vector2{ .x = @floatFromInt(pos_component.x), .y = @floatFromInt(pos_component.y) };

        // TODO: error handling
        const texture = am.hashmap.get(c.texture_hash) orelse @panic("Texture not found");

        rl.drawTextureEx(texture, pos, rotation(c), scale(c), c.tint);
    }
}

pub inline fn rotation(texture: *ecs.component.Tex) f32 {
    return switch (texture.rotate) {
        .R0 => 0,
        .R90 => 0,
        .R180 => 0,
        .R270 => 0,
    };
}

pub inline fn scale(texture: *ecs.component.Tex) f32 {
    return @floatCast(texture.scale.toFloat());
}
