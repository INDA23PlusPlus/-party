const rl = @import("raylib");
const std = @import("std");
const ecs = @import("ecs/ecs.zig");

const map_type = std.HashMap(
    u64,
    rl.Texture2D,
    Context,
    std.hash_map.default_max_load_percentage,
);

textures: map_type,
bc_color: rl.Color,
world: *ecs.World,

pub const TextureComponent = struct {
    texture_hash: u64,
    tint: rl.Color,
    rotation: f32,
    scale: f32,
};

const Context = struct {
    pub const hash = struct {
        pub fn hash(self: Context, key: u64) u64 {
            _ = self;
            return key;
        }
    }.hash;
    pub const eql = struct {
        pub fn eql(self: Context, a: u64, b: u64) bool {
            _ = self;
            return a == b;
        }
    }.eql;
};

const Self = @This();

pub fn init(allocator: std.mem.Allocator, world: *ecs.World, background_color: rl.Color) @This() {
    return .{
        .world = world,
        .textures = map_type.init(allocator),
        .bc_color = background_color,
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.textures.valueIterator();
    while (iter.next()) |texture| {
        rl.unloadTexture(texture.*);
    }

    self.textures.deinit();
}

pub fn update(self: *Self) void {
    rl.clearBackground(self.bc_color);

    var query = self.world.query(&.{ ecs.Position, TextureComponent }, &.{});
    while (query.next()) |_| {
        const pos_component = query.get(ecs.Position) catch unreachable;
        const c = query.get(TextureComponent) catch unreachable;

        const pos = rl.Vector2{ .x = @floatFromInt(pos_component.x), .y = @floatFromInt(pos_component.y) };
        const texture = self.textures.get(c.texture_hash) orelse @panic("Texture not found");

        rl.drawTextureEx(texture, pos, c.scale, c.rotation, c.tint);
    }
}

// could maybe make a generic resource loader to use for all resource based systems
/// loads a texture from a path and
/// returns the texture hash that is used to make a texture component
pub fn load_texture(self: *Self, path: [:0]const u8) !u64 {
    const hash = std.hash.Wyhash.hash(0, path);

    if (self.textures.contains(hash)) {
        return hash;
    }

    const texture = rl.loadTexture(path);
    try self.textures.put(hash, texture);
    return hash;
}
