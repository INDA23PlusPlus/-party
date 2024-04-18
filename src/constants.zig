const rl = @import("raylib");

/// 8 players (and 8 possible spectators)
pub const max_connected_count = 16;

/// WASD + IJKL + 8 gamepads
pub const max_controller_count = 10;

/// The 8 players walking around the world
pub const max_player_count = 8;

/// What is the average pixel width of our smaller assets (as well as tiles).
pub const asset_resolution = 16;

// Width of the world in pixels.
pub const world_width = 512;

// Height of the world in pixels.
pub const world_height = 288;

// The color hint of each player.
pub const player_colors: [max_player_count]rl.Color = .{
    rl.Color.white,
    rl.Color.red,
    rl.Color.green,
    rl.Color.blue,
    rl.Color.yellow,
    rl.Color.pink,
    rl.Color.orange,
    rl.Color.black,
};
