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
};

pub fn data(animation: Animation) []const Frame {
    return switch (animation) {
        Animation.Default => &frames_default,
        Animation.KattisIdle => &frames_kattis_idle,
        Animation.KattisRun => &frames_kattis_run,
        Animation.KattisFly => &frames_kattis_fly,
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

pub const Frame = struct {
    u: u32,
    v: u32,

    pub fn init(u: u32, v: u32) Frame {
        return Frame{ .u = u, .v = v };
    }
};
