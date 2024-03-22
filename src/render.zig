const rl = @import("raylib");
const std = @import("std");
const root = @import("root");
const builtin = @import("builtin");

// TODO: this will come from ecs later
fn ecs_texture_component_list(self: *@This()) [1]TextureComponent {
    return .{
        TextureComponent{
            .texture = self.get_texture() catch @panic("Failed to load texture"),
            .tint = rl.Color.white,
            .rotation = 0.0,
            .scale = 1.0,
        },
        // TextureComponent{
        //     .texture = self.get_texture(@as([]const u8, "assets/texture.png")),
        //     .tint = rl.Color.white,
        //     .rotation = 0.0,
        //     .scale = 1.0,
        // },
    };
}

sprites: std.StringHashMap(rl.Texture2D),
bc_color: rl.Color,

pub fn init(allocator: std.mem.Allocator, color: rl.Color) @This() {
    return .{
        .sprites = std.StringHashMap(rl.Texture2D).init(allocator),
        .bc_color = color,
    };
}

pub fn deinit(self: *@This()) void {
    var iter = self.sprites.valueIterator();
    while (iter.next()) |texture| {
        rl.unloadTexture(texture.*);
    }
    self.sprites.deinit();
}

pub fn update(self: *@This()) void {
    rl.clearBackground(self.bc_color);

    for (self.ecs_texture_component_list()) |c| {
        // TODO: pos needs to come from ecs
        const pos = rl.Vector2{ .x = 0, .y = 0 };
        rl.drawTextureEx(c.texture.*, pos, c.rotation, c.scale, c.tint);
    }
}

// could maybe make a generic resource loader to use for all resource based systems
pub fn get_texture(self: *@This()) !*const rl.Texture2D {
    const file_name = "assets/test.png";
    if (self.sprites.get(file_name)) |texture| {
        return &texture;
    }

    // TODO: load from only file name
    var texture = rl.loadTexture(file_name);
    try self.sprites.put(file_name, texture);
    return &texture;
}

pub const TextureComponent = struct {
    texture: *const rl.Texture2D,
    tint: rl.Color,
    rotation: f32,
    scale: f32,
};
