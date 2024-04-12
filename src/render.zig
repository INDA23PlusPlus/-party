const rl = @import("raylib");
const std = @import("std");
const ecs = @import("ecs/ecs.zig");
const AssetManager = @import("AssetManager.zig");
const constants = @import("constants.zig");

pub fn update(world: *ecs.world.World, am: *AssetManager) void {
    // var view = View.init(100, 100);
    // view.render(world, am);
    // view.deinit();

    var query = world.query(&.{ ecs.component.Pos, ecs.component.Tex }, &.{});

    while (query.next()) |_| {
        const pos_component = query.get(ecs.component.Pos) catch unreachable;
        const tex_component = query.get(ecs.component.Tex) catch unreachable;

        const pos = rl.Vector2{ .x = @floatFromInt(pos_component.pos[0]), .y = @floatFromInt(pos_component.pos[1]) };

        // TODO: error handling

        const tex = am.hashmap.get(tex_component.texture_hash) orelse @panic("Texture not found");

        const src = rl.Rectangle{
            .x = @floatFromInt(tex_component.u * constants.asset_resolution),
            .y = @floatFromInt(tex_component.v * constants.asset_resolution),
            .width = @floatFromInt(constants.asset_resolution),
            .height = @floatFromInt(constants.asset_resolution),
        };

        const dst = rl.Rectangle{
            .x = pos.x,
            .y = pos.y,
            .width = constants.asset_resolution * 4,
            .height = constants.asset_resolution * 4,
        };

        // ! rotation unused
        rl.drawTexturePro(tex, src, dst, rl.Vector2.init(0, 0), 0.0, tex_component.tint);

        // rl.drawTextureEx(texture, pos, 0, @floatCast(c.scale.toFloat()), c.tint);
    }
}

/// Represents a section of a window for rendering a world.
pub const View = struct {
    const Self = @This();

    const width = 640; // TODO: Move elsewhere
    const height = 320; // TODO: Move elsewhere

    dst: rl.Rectangle,
    src: rl.Rectangle,
    tex: rl.RenderTexture2D,

    pub fn init(x: f32, y: f32) Self {
        const dst = rl.Rectangle.init(x, y, width, height);
        const src = rl.Rectangle.init(0.0, 0.0, width, -height);
        const tex = rl.loadRenderTexture(width, height);

        return Self{
            .dst = dst,
            .src = src,
            .tex = tex,
        };
    }

    pub fn deinit(self: *Self) void {
        rl.unloadRenderTexture(self.tex);
    }

    pub fn draw(view: *Self, world: *ecs.world.World, assets: *AssetManager) void {
        rl.beginTextureMode(view.tex);
        rl.clearBackground(rl.Color.black);
        rl.drawText("MINIGAME WINDOW", 0, 0, 2, rl.Color.gold);

        var query = world.query(&.{ ecs.component.Pos, ecs.component.Tex }, &.{});
        while (query.next()) |_| {
            const pos = query.get(ecs.component.Pos) catch unreachable;
            const tex = query.get(ecs.component.Tex) catch unreachable;

            const texture = assets.hashmap.get(tex.texture_hash) orelse @panic("Texture not found");
            const position = toVector2(pos);
            const rotation, const scale = transform(tex);
            const tint = tex.tint;

            rl.drawTextureEx(texture, position, rotation, scale, tint);
        }

        // Temp
        rl.drawText("MINIGAME WINDOW", 0, 0, 2, rl.Color.gold);

        rl.endTextureMode();

        const origin = rl.Vector2.init(0.0, 0.0);
        const rotation = 0.0;

        rl.drawTexturePro(view.tex.texture, view.src, view.dst, origin, rotation, rl.Color.white);
    }

    inline fn transform(tex: *ecs.component.Tex) struct { f32, f32 } {
        const rotation: f32 = switch (tex.rotate) {
            .R0 => 0.0,
            .R90 => 90.0,
            .R180 => 180.0,
            .R270 => 270.0,
        };

        const mirror: f32 = if (tex.mirror) -1.0 else 1.0;

        const scale: f32 = @floatCast(tex.scale.toFloat());

        return .{ rotation, scale * mirror };
    }

    inline fn toVector2(pos: *ecs.component.Pos) rl.Vector2 {
        return rl.Vector2.init(
            @as(f32, @floatFromInt(pos.pos[0])),
            @as(f32, @floatFromInt(pos.pos[1])),
        );
    }
};
