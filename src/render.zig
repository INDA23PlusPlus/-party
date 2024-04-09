const rl = @import("raylib");
const std = @import("std");
const ecs = @import("ecs/ecs.zig");
const AssetManager = @import("AssetManager.zig");

pub fn update(world: *ecs.world.World, am: *AssetManager) void {
    const view = View.init(.{ 100, 200 });
    view.render(world, am);

    var query = world.query(&.{ ecs.component.Pos, ecs.component.Tex }, &.{});

    while (query.next()) |_| {
        const pos_component = query.get(ecs.component.Pos) catch unreachable;
        const c = query.get(ecs.component.Tex) catch unreachable;

        const pos = rl.Vector2{ .x = @floatFromInt(pos_component.vec[0]), .y = @floatFromInt(pos_component.vec[1]) };

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

/// Just experimenting.
/// Represents a subsection of the window where entities can be rendered too.
const View = struct {
    position: @Vector(2, i32),
    width: i32,
    height: i32,

    pub fn init(position: @Vector(2, i32)) @This() {
        return .{ .position = position, .width = 640, .height = 320 };
    }

    pub fn render(view: @This(), world: *ecs.world.World, assets: *AssetManager) void {
        var query = world.query(&.{ ecs.component.Pos, ecs.component.Tex }, &.{});
        while (query.next()) |_| {
            const pos = view.position + (query.get(ecs.component.Pos) catch unreachable).vec;
            const tex = query.get(ecs.component.Tex) catch unreachable;

            const position = rl.Vector2.init(@floatFromInt(pos[0]), @floatFromInt(pos[1]));
            const texture = assets.hashmap.get(tex.texture_hash) orelse @panic("Texture not found");
            const rotation_ = rotation(tex);
            const scale_ = scale(tex);
            const tint = tex.tint;

            rl.drawRectangle(view.position[0], view.position[1], view.width, view.height, rl.Color.blue);
            rl.drawTextureEx(texture, position, rotation_, scale_, tint);
        }
    }
};
