/// Only add data that is consistently the same accross the start of all frames.
/// Example:
/// - An allocator that has been reset.
/// - The list of compiled minigames.

const Minigame = @import("minigames/Minigame.zig");
const std = @import("std");

minigames_list: []const Minigame,
arena: std.mem.Allocator
