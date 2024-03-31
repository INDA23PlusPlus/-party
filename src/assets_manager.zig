const std = @import("std");
const rl = @import("raylib");
const root = @import("root");

// pub fn pathHash(self: u64) u64 {
//     return std.hash.Wyhash.hash(0, self);
// }
//
// const Context = struct {
//     pub const hash = struct {
//         pub fn hash(self: Context, key: u64) u64 {
//             _ = self;
//             return key;
//         }
//     }.hash;
//     pub const eql = struct {
//         pub fn eql(self: Context, a: u64, b: u64) bool {
//             _ = self;
//             return a == b;
//         }
//     }.eql;
// };
//
// const map_type = std.HashMap(
//     u64,
//     rl.Texture2D,
//     Context,
//     std.hash_map.default_max_load_percentage,
// );

pub fn AssetsEnum(asset_paths: []const []const u8) type {
    var enum_fields: [asset_paths.len]std.builtin.Type.EnumField = undefined;
    var declerations: [asset_paths.len]std.builtin.Type.Decleration = undefined;

    for (asset_paths, 0..) |path, i| {
        enum_fields[i] = std.builtin.Type.EnumField{ .name = path, .value = i };
        declerations[i] = std.builtin.Type.Declaration{
            .name = path,
        };
    }

    return @Type(std.builtin.Type.Enum{
        .tag_type = u16,
        .fields = &enum_fields,
        .decls = &declerations,
        .is_exhaustive = true,
    });
}

pub fn AssetsManager(game: *root.Game) type {
    return struct {
        hashmap: std.AutoHashMap(game.assets(), rl.Texture2D),

        const Self = @This();

        pub fn init(allocator: *std.mem.Allocator) Self {
            var hashmap = @TypeOf(Self.hashmap).init(allocator);

            for (game.assets_paths) |path| {
                const enum_field = std.meta.stringToEnum(game.assets(), path);

                if (hashmap.contains(enum_field)) {
                    continue;
                }

                const texture = rl.loadTexture(path);
                try hashmap.put(enum_field, texture);
            }

            return Self{
                .textures = hashmap,
            };
        }

        pub fn deinit(self: *Self) void {
            var iter = self.textures.valueIterator();
            while (iter.next()) |texture| {
                rl.unloadTexture(texture.*);
            }

            self.textures.deinit();
        }
    };
}
