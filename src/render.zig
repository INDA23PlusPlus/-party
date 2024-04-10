const rl = @import("raylib");
const std = @import("std");
const ecs = @import("ecs/ecs.zig");
const AssetManager = @import("AssetManager.zig");

pub fn update(world: *ecs.world.World, am: *AssetManager) void {
    const view = View.init(100, 200);
    view.render(world, am);

    var query = world.query(&.{ ecs.component.Pos, ecs.component.Tex }, &.{});

    while (query.next()) |_| {
        const pos_component = query.get(ecs.component.Pos) catch unreachable;
        const c = query.get(ecs.component.Tex) catch unreachable;

        const pos = rl.Vector2{ .x = @floatFromInt(pos_component.vec[0]), .y = @floatFromInt(pos_component.vec[1]) };

        // TODO: error handling
        const texture = am.hashmap.get(c.texture_hash) orelse @panic("Texture not found");

        rl.drawTextureEx(texture, pos, 0, @floatCast(c.scale.toFloat()), c.tint);
    }
}

/// Just experimenting.
/// Represents a subsection of the window where entities can be rendered too.
const View = struct {
    x: i32,
    y: i32,
    texture: rl.RenderTexture2D,

    pub fn init(x: i32, y: i32) @This() {
        const texture = rl.loadRenderTexture(640, 320);
        return .{
            .x = x,
            .y = y,
            .texture = texture,
        };
    }

    pub fn render(view: @This(), world: *ecs.world.World, assets: *AssetManager) void {
        rl.drawRectangle(view.x, view.y, view.texture.texture.width, view.texture.texture.height, rl.Color.blue);
        rl.beginTextureMode(view.texture);

        var query = world.query(&.{ ecs.component.Pos, ecs.component.Tex }, &.{});
        while (query.next()) |_| {
            const pos = query.get(ecs.component.Pos) catch unreachable;
            const tex = query.get(ecs.component.Tex) catch unreachable;

            const position = rl.Vector2.init(
                @floatFromInt(pos.vec[0] + view.x),
                @floatFromInt(pos.vec[1] + view.y),
            );
            const texture = assets.hashmap.get(tex.texture_hash) orelse @panic("Texture not found");
            const rotation, const scale = transform(tex);
            const tint = tex.tint;

            rl.drawTextureEx(texture, position, rotation, scale, tint);
        }

        rl.endTextureMode();
        rl.drawTexture(view.texture.texture, view.x, view.y, rl.Color.white);
    }

    pub fn transform(texture: *ecs.component.Tex) struct { f32, f32 } {
        const rotation: f32 = switch (texture.rotate) {
            .R0 => 0.0,
            .R90 => 90.0,
            .R180 => 180.0,
            .R270 => 270.0,
        };

        const scale: f32 = @floatCast(texture.scale.toFloat());

        return .{ rotation, scale };
    }
};
