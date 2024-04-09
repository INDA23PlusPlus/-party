const minigame = @import("interface.zig");

const example = @import("example.zig");

/// Create a list of Minigames.
pub const list = [_]minigame.Minigame{
    .{
        .update = example.update,
        .init = example.init,
    }
};
