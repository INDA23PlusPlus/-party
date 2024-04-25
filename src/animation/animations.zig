const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const input = @import("../input.zig");
const constants = @import("../constants.zig");

pub const Animation = enum {
    Default,
    KattisIdle,
    KattisRun,
    KattisFly,
    TronSkull,
    SmashIdle,
    SmashRun,
    SmashJump,
    SmashFall,
    SmashLand,
};

pub fn data(animation: Animation) []const Frame {
    return switch (animation) {
        .Default => &frames_default,
        .KattisIdle => &frames_kattis_idle,
        .KattisRun => &frames_kattis_run,
        .KattisFly => &frames_kattis_fly,
        .TronSkull => &frames_tron_skull,
        .SmashIdle => &frames_smash_idle,
        .SmashRun => &frames_smash_run,
        .SmashJump => &frames_smash_jump,
        .SmashFall => &frames_smash_fall,
        .SmashLand => &frames_smash_land,
    };
}

const frames_default: [1]Frame = .{
    Frame.init(0, 0),
};

const frames_kattis_idle: [4]Frame = .{
    Frame.init(0, 0),
    Frame.init(1, 0),
    Frame.init(2, 0),
    Frame.init(3, 0),
};

const frames_kattis_run: [3]Frame = .{
    Frame.init(0, 1),
    Frame.init(1, 1),
    Frame.init(2, 1),
};

const frames_kattis_fly: [4]Frame = .{
    Frame.init(0, 2),
    Frame.init(1, 2),
    Frame.init(2, 2),
    Frame.init(3, 2),
};

const frames_tron_skull: [4]Frame = .{
    Frame.init(0, 0),
    Frame.init(1, 0),
    Frame.init(2, 0),
    Frame.init(3, 0),
};

const frames_smash_idle: [4]Frame = .{
    Frame.init(0, 0),
    Frame.init(2, 0),
    Frame.init(4, 0),
    Frame.init(6, 0),
};

const frames_smash_run: [8]Frame = .{
    Frame.init(0, 4),
    Frame.init(2, 4),
    Frame.init(4, 4),
    Frame.init(6, 4),
    Frame.init(8, 4),
    Frame.init(10, 4),
    Frame.init(12, 4),
    Frame.init(14, 4),
};

const frames_smash_jump: [3]Frame = .{
    Frame.init(0, 8),
    Frame.init(2, 8),
    Frame.init(4, 8),
};

const frames_smash_fall: [2]Frame = .{
    Frame.init(6, 8),
    Frame.init(8, 8),
};

const frames_smash_land: [2]Frame = .{
    Frame.init(10, 8),
    Frame.init(12, 8),
};

pub const Frame = struct {
    u: u32,
    v: u32,

    pub fn init(u: u32, v: u32) Frame {
        return Frame{ .u = u, .v = v };
    }
};

// 0  1  2  3  4
// 5  6
// 10 11
