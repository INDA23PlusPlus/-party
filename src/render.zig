const rl = @import("raylib");
const std = @import("std");
const ecs = @import("ecs/ecs.zig");
const AssetManager = @import("AssetManager.zig");
const constants = @import("constants.zig");
const win = @import("window.zig");

pub fn update(world: *ecs.world.World, am: *AssetManager, window: *win.Window) void {
    var query = world.query(&.{ ecs.component.Pos, ecs.component.Tex }, &.{});

    while (query.next()) |_| {
        const pos_component = query.get(ecs.component.Pos) catch unreachable;
        const tex_component = query.get(ecs.component.Tex) catch unreachable;

        const tex = am.hashmap.get(tex_component.texture_hash) orelse am.hashmap.get(AssetManager.pathHash("assets/default.png")) orelse unreachable;

        // Src

        const src_x: f32 = @floatFromInt(tex_component.u * constants.asset_resolution);
        const src_y: f32 = @floatFromInt(tex_component.v * constants.asset_resolution);
        const src_w: f32 = @floatFromInt(tex_component.w * constants.asset_resolution);
        const src_h: f32 = @floatFromInt(tex_component.h * constants.asset_resolution);

        const src = rl.Rectangle{ .x = src_x, .y = src_y, .width = src_w, .height = src_h };

        // Dst

        const scaling: @Vector(2, f32) = .{
            @as(f32, @floatFromInt(window.width)) / constants.world_width,
            @as(f32, @floatFromInt(window.height)) / constants.world_height,
        };

        const dst_pos = @as(@Vector(2, f32), @floatFromInt(pos_component.pos + tex_component.subpos)) * scaling;

        const dst_x = dst_pos[0];
        const dst_y = dst_pos[1];
        const dst_w = src_w * scaling[0];
        const dst_h = src_h * scaling[1];

        const dst = rl.Rectangle{ .x = dst_x, .y = dst_y, .width = dst_w, .height = dst_h };

        // Draw

        rl.drawTexturePro(tex, src, dst, rl.Vector2.init(0, 0), 0.0, tex_component.tint);
    }

    var text_query = world.query(&.{ ecs.component.Pos, ecs.component.Txt }, &.{});

    // Draw text
    while (text_query.next()) |_| {
        const pos_component = text_query.get(ecs.component.Pos) catch unreachable;
        const text_c = text_query.get(ecs.component.Txt) catch unreachable;

        if (text_c.draw == false) continue; // Ugly, can be fixed with dynamic strings for text??

        const color = rl.Color.fromInt(text_c.color);
        const pos = pos_component.pos + text_c.subpos;
        const pos_x = pos[0];
        const pos_y = pos[1];

        const font_size_scaled = @as(f32, @floatFromInt(text_c.font_size * window.height)) * 138889.0 / 50000000.0; // Super specific magic number go brrrrr

        const text_dim_x = rl.measureText(text_c.string, @intFromFloat(font_size_scaled));
        const text_width_half: i32 = @divFloor(text_dim_x, 2);
        const text_height_half: i32 = @intFromFloat(font_size_scaled * (1.0 / 3.0));

        const dst_x = @divFloor(pos_x * window.width, constants.world_width) - text_width_half;
        const dst_y = @divFloor(pos_y * window.height, constants.world_height) - text_height_half;

        rl.drawText(text_c.string, dst_x, dst_y, @intFromFloat(font_size_scaled), color);
    }
}
