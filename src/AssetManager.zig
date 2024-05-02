const std = @import("std");
const rl = @import("raylib");

pub const default_path = "assets/default.png";
pub const default_hash = pathHash(default_path);

pub fn pathHash(path: []const u8) u64 {
    return std.hash.Wyhash.hash(0, path);
}

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

// TODO: generalized to handle other asset types
const map_type = std.HashMap(
    u64,
    rl.Texture2D,
    Context,
    std.hash_map.default_max_load_percentage,
);

const paths = [_][:0]const u8{
    default_path,
    "assets/test.png",
    "assets/kattis.png",
    "assets/tron_map.png",
    "assets/smash_background_0.png",
    "assets/smash_background_1.png",
    "assets/smash_background_2.png",
    "assets/smash_platform.png",
    "assets/smash_jump_smoke.png",
    "assets/tron_skull.png",
    "assets/smash_cat.png",
    "assets/error.png",
    "assets/borggarden.png",
    "assets/kattis_testcases.png",
    "assets/sky_background_0.png",
    "assets/sky_background_1.png",
    "assets/sky_background_2.png",
};

hashmap: map_type,
const Self = @This();
// var buffer: [@sizeOf(@TypeOf(paths)) + @sizeOf(rl.Texture2D) * paths.len + 5000]u8 = undefined;

pub fn init(allocator: std.mem.Allocator) Self {
    // var fixed_allocator = std.heap.FixedBufferAllocator.init(&buffer);
    // const allocator = fixed_allocator.allocator();

    var map = map_type.init(allocator);
    for (paths) |path| {
        const key = pathHash(path);
        if (map.contains(key)) {
            continue;
        }

        const texture = rl.loadTexture(path);
        map.put(key, texture) catch unreachable;
    }

    return Self{
        .hashmap = map,
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.hashmap.valueIterator();
    while (iter.next()) |texture| {
        rl.unloadTexture(texture.*);
    }

    self.hashmap.deinit();
}
