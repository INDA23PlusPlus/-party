const minigame = @import("interface.zig");

const example = @import("example.zig");
const morsecode = @import("morsecode.zig");
const tron = @import("tron.zig");
const hot_n_steamy = @import("hot_n_steamy.zig");

/// Create a list of Minigames.
pub const list = [_]minigame.Minigame{
    .{
        .name = "example",
        .update = example.update,
        .init = example.init,
    },
    .{
        .name = "morsecode",
        .update = morsecode.update,
        .init = morsecode.init,
    },
    .{
        .name = "tron",
        .update = tron.update,
        .init = tron.init,
    },
    .{
        .name = "hot_n_steamy",
        .update = hot_n_steamy.update,
        .init = hot_n_steamy.init,
    },
};
