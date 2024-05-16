const std = @import("std");
const rl = @import("raylib");
const constants = @import("constants.zig");

pub const default_path = "assets/default.png";
pub const default_hash = pathHash(default_path);

const paths = [_][:0]const u8{
    default_path,
    "assets/test.png",
    "assets/kattis.png",
    "assets/tron_map.png",
    "assets/podium_piece.png",
    "assets/smash_background_0.png",
    "assets/smash_background_1.png",
    "assets/smash_background_2.png",
    "assets/smash_sun.png",
    "assets/smash_platform.png",
    "assets/smash_jump_smoke.png",
    "assets/smash_attack_smoke.png",
    "assets/smash_death.png",
    "assets/tron_skull.png",
    "assets/smash_cat.png",
    "assets/error.png",
    "assets/BABBA.png",
    "assets/morsetable.png",
    "assets/morsecode_background.png",
    "assets/borggarden.png",
    "assets/kattis_testcases.png",
    "assets/tmp.png",
    "assets/sky_background_0.png",
    "assets/sky_background_1.png",
    "assets/sky_background_2.png",
    "assets/crown.png",
    "assets/monogram_bitmap.png",
    "assets/roulette.png",
    "assets/menu.png",
    "assets/cat_portrait.png",
    "assets/lobby.png",
    "assets/gamewheel.png",
    "assets/monogram-bitmap-2.png",
    "assets/background_animated.png",
};

pub const default_string = "DEFAULT STRING";
pub const default_string_hash = pathHash(default_string);

// ------------------ GENERATE STRINGS ----------------------
const strings = [_][:0]const u8{
    default_string,
    "test",
    "++PARTY",
} ++ player_strings ++ game_strings;

const player_strings: [constants.max_player_count][:0]const u8 = blk: {
    var res: [constants.max_player_count][:0]const u8 = undefined;
    for (0..constants.max_player_count) |id| {
        res[id] = "Player " ++ std.fmt.comptimePrint("{}", .{id});
    }
    break :blk res;
};

const game_strings = [_][:0]const u8{
    "BABBA",
    "TEST",
    "WORD",
    "PLUSPLUS",
    "KTH",
    "DATA",
    "RAUNAK",
    "ERIK",
};

// ----------------------------------------------------------

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

const text_map_type = std.HashMap(
    u64,
    [:0]const u8,
    Context,
    std.hash_map.default_max_load_percentage,
);

const texture_map_type = std.HashMap(
    u64,
    rl.Texture2D,
    Context,
    std.hash_map.default_max_load_percentage,
);

font: rl.Font,
texture_map: texture_map_type,
text_map: text_map_type,
const Self = @This();
// var buffer: [@sizeOf(@TypeOf(paths)) + @sizeOf(rl.Texture2D) * paths.len + 5000]u8 = undefined;

pub fn init(allocator: std.mem.Allocator) Self {
    // var fixed_allocator = std.heap.FixedBufferAllocator.init(&buffer);
    // const allocator = fixed_allocator.allocator();

    var texture_map = texture_map_type.init(allocator);
    for (paths) |path| {
        const key = pathHash(path);
        if (texture_map.contains(key)) {
            continue;
        }

        const texture = rl.loadTexture(path);
        texture_map.put(key, texture) catch unreachable;
    }

    var text_map = text_map_type.init(allocator);
    for (strings) |string| {
        const key = pathHash(string);
        if (text_map.contains(key)) {
            continue;
        }

        text_map.put(key, string) catch unreachable;
    }

    const font = rl.loadFont("assets/monogram.ttf");

    return Self{
        .font = font,
        .texture_map = texture_map,
        .text_map = text_map,
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.texture_map.valueIterator();
    while (iter.next()) |texture| {
        rl.unloadTexture(texture.*);
    }

    rl.unloadFont(self.font);
    self.texture_map.deinit();
    self.text_map.deinit();
}
