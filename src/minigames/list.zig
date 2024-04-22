const minigame = @import("interface.zig");

const menu = @import("menu.zig");
const morsecode = @import("morsecode.zig");
const tron = @import("tron.zig");
const smash = @import("smash.zig");
const hot_n_steamy = @import("hot_n_steamy.zig");
const lobby = @import("lobby.zig");
const example = @import("example.zig");

/// Create a list of Minigames.
pub const list = [_]minigame.Minigame{
    .{
        .name = "menu",
        .update = menu.update,
        .init = menu.init,
    },
    .{
        .name = "lobby",
        .update = lobby.update,
        .init = lobby.init,
    },
        // .{
        //     .name = "example",
        //     .update = example.update,
        //     .init = example.init,
        // },
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
        .name = "smash",
        .update = smash.update,
        .init = smash.init,
    },
    .{
        .name = "hns",
        .update = hot_n_steamy.update,
        .init = hot_n_steamy.init,
    },
};
