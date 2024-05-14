const rl = @import("raylib");

/// 8 players (and 8 possible spectators)
pub const max_connected_count = 16;

/// WASD + IJKL + 8 gamepads
pub const max_controller_count = 10;

/// The 8 players walking around the world
pub const max_player_count = 8;

/// What is the average pixel width of our smaller assets (as well as tiles).
pub const asset_resolution = 16;

/// Width of the world in pixels.
pub const world_width = 512;

// Height of the world in pixels.
pub const world_height = 288;

pub const world_width_tiles = world_width / asset_resolution;
pub const world_height_tiles = world_height / asset_resolution;

pub const ticks_per_second = 60;

/// The color hint of each player.
pub const player_colors: [max_player_count]rl.Color = .{
    rl.Color.white,
    rl.Color.red,
    rl.Color.green,
    rl.Color.blue,
    rl.Color.gray,
    rl.Color.magenta,
    rl.Color.sky_blue,
    rl.Color.violet,
};

// TODO: This is really ugly. But it is better than introducing a circular dependency.
// TODO: What one should do instead is add a findMinigame to Invariables as it has the list of minigames (without introducing a circular dependency)
// TODO: This is already done in lobby.zig, so it could be used as reference. Feel free to refactor.
pub const minigame_scoreboard = 4;
pub const minigame_gamewheel = 6;
