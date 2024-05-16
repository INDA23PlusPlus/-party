const std = @import("std");
const rl = @import("raylib");

const Allocator = std.mem.Allocator;

const Context = struct {
    pub const hash = struct {
        pub fn hash(self: Context, key: u8) u64 {
            _ = self;
            return @intCast(key);
        }
    }.hash;
    pub const eql = struct {
        pub fn eql(self: Context, a: u8, b: u8) bool {
            _ = self;
            return a == b;
        }
    }.eql;
};

const AudioHashMap = std.HashMap(
    u8,
    rl.Sound,
    Context,
    std.hash_map.default_max_load_percentage,
);

pub const default_audio = "assets/audio/default.wav";
const audio_paths = [_][:0]const u8{
    default_audio,
};

pub fn path_to_key(comptime path: [:0]const u8) u8 {
    comptime {
        return @truncate(std.hash.Wyhash.hash(0, path));
    }
}

pub const AudioManager = struct {
    const Self = @This();
    audio_map: AudioHashMap,

    pub fn init(alloc: Allocator) !AudioManager {
        rl.initAudioDevice();
        var audio_hash_map = AudioHashMap.init(alloc);
        for (audio_paths) |path| {
            const key: u8 = @truncate(std.hash.Wyhash.hash(0, path));
            const sound = rl.loadSound(path);
            try audio_hash_map.put(key, sound);
        }

        return .{ .audio_map = audio_hash_map };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.audio_map.valueIterator();
        while (iter.next()) |sound| {
            rl.unloadSound(sound.*);
        }
        self.audio_map.deinit();
        rl.closeAudioDevice();
    }
};
