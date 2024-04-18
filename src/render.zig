const rl = @import("raylib");
const std = @import("std");
const ecs = @import("ecs/ecs.zig");
const AssetManager = @import("AssetManager.zig");
const constants = @import("constants.zig");
const win = @import("window.zig");

pub fn update(world: *ecs.world.World, am: *AssetManager, window: *win.Window) void {
    var query = world.query(&.{ ecs.component.Pos, ecs.component.Tex }, &.{});
    var text_query = world.query(&.{ ecs.component.Pos, ecs.component.Txt }, &.{});

    while (query.next()) |_| {
        const pos_component = query.get(ecs.component.Pos) catch unreachable;
        const tex_component = query.get(ecs.component.Tex) catch unreachable;

        const pos = rl.Vector2{ .x = @floatFromInt(pos_component.pos[0]), .y = @floatFromInt(pos_component.pos[1]) };

        // TODO: error handling

        const tex = am.hashmap.get(tex_component.texture_hash) orelse @panic("Texture not found");

        const u: f32 = @floatFromInt(tex_component.u * constants.asset_resolution);
        const v: f32 = @floatFromInt(tex_component.v * constants.asset_resolution);
        const w: f32 = @floatFromInt(tex_component.tiles_x * constants.asset_resolution);
        const h: f32 = @floatFromInt(tex_component.tiles_y * constants.asset_resolution);

        const src = rl.Rectangle{
            .x = u,
            .y = v,
            .width = w,
            .height = h,
        };

        // Convert internal range to window range.
        const dst_x = ((pos.x * @as(f32, @floatFromInt(window.width))) / constants.world_width);
        const dst_y = ((pos.y * @as(f32, @floatFromInt(window.height))) / constants.world_height);
        const dst_w = ((w * @as(f32, @floatFromInt(window.width))) / constants.world_width);
        const dst_h = ((h * @as(f32, @floatFromInt(window.height))) / constants.world_height);

        const dst = rl.Rectangle{
            .x = dst_x,
            .y = dst_y,
            .width = dst_w,
            .height = dst_h,
        };

        // ! rotation unused
        rl.drawTexturePro(tex, src, dst, rl.Vector2.init(0, 0), 0.0, tex_component.tint);

        // rl.drawTextureEx(texture, pos, 0, @floatCast(c.scale.toFloat()), c.tint);
    }

    // Draw text
    while (text_query.next()) |_| {
        const pos_component = text_query.get(ecs.component.Pos) catch unreachable;
        const text_c = text_query.get(ecs.component.Txt) catch unreachable;

        if (text_c.draw == false) continue; // Ugly, can be fixed with dynamic strings for text??

        const col = rl.Color.fromInt(text_c.color);
        const pos_x = pos_component.pos[0];
        const pos_y = pos_component.pos[1];

        const font = rl.getFontDefault();
        const text_dims = rl.measureTextEx(font, text_c.string, @floatFromInt(text_c.font_size), 0.0);
        const text_width_half: i32 = @intFromFloat(text_dims.x / 2.0);
        const text_height_half: i32 = @intFromFloat(text_dims.y / 2.0);

        const dst_x = @divFloor(pos_x * window.width, constants.world_width) - text_width_half;
        const dst_y = @divFloor(pos_y * window.height, constants.world_height) - text_height_half;

        rl.drawText(text_c.string, dst_x, dst_y, @intCast(text_c.font_size), col);
    }
}

/// Represents a section of a window for rendering a world.
pub const View = struct {
    const Self = @This();

    const width = constants.world_width;
    const height = constants.world_height;

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
