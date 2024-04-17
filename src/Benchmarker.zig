// A shitty benchmarker

const std = @import("std");

const Self = @This();

name: []const u8,
timer: std.time.Timer,
time: u64,
laps: u64,
out: std.fs.File,

pub fn init(name: []const u8) !Self {
    return Self{
        .name = name,
        .timer = try std.time.Timer.start(),
        .time = 0,
        .laps = 0,
        .out = std.io.getStdOut(),
    };
}

pub fn start(self: *Self) void {
    self.timer.reset();
}

pub fn stop(self: *Self) void {
    self.time += self.timer.read();
    self.laps += 1;
}

pub fn write(self: *Self) !void {
    const writer = self.out.writer();

    try writer.print("{s}:\n", .{self.name});

    const t: f64 = @floatFromInt(self.time);
    const l: f64 = @floatFromInt(self.laps);

    const ns_per_lap = t / l;
    const ms_per_lap = ns_per_lap / std.time.ns_per_ms;
    try writer.print(" - {d:>.4} ms/lap \n", .{ms_per_lap});

    const laps_per_ns = l / t;
    const laps_per_ms = laps_per_ns * std.time.ns_per_ms;
    try writer.print(" - {d:>.4} laps/ms \n", .{laps_per_ms});

    const frames_per_lap = ms_per_lap / 17.0;
    try writer.print(" - {d:>.4} frames/lap \n", .{frames_per_lap});

    const laps_per_frame = laps_per_ms * 17.0;
    try writer.print(" - {d:>.4} laps/frame \n", .{laps_per_frame});
}

pub fn reset(self: *Self) void {
    self.time = 0;
    self.laps = 0;
}
