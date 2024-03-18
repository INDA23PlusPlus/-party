const std = @import("std");
const rl = @import("raylib-zig/build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    var raylib = rl.getModule(b, "raylib-zig");
    var raylib_math = rl.math.getModule(b, "raylib-zig");
    if (target.getOsTag() == .emscripten) {
        const exe_lib = rl.compileForEmscripten(b, "++party", "src/main.zig", target, optimize);
        exe_lib.addModule("raylib", raylib);
        exe_lib.addModule("raylib-math", raylib_math);
        const raylib_artifact = rl.getRaylib(b, target, optimize);
        exe_lib.linkLibrary(raylib_artifact);
        const link_step = try rl.linkWithEmscripten(b, &[_]*std.Build.Step.Compile{ exe_lib, raylib_artifact });
        b.getInstallStep().dependOn(&link_step.step);
        const run_step = try rl.emscriptenRunStep(b);
        run_step.step.dependOn(&link_step.step);
        const run_option = b.step("run", "Run ++party");
        run_option.dependOn(&run_step.step);
        return;
    }

    const exe = b.addExecutable(.{ 
        .name = "++party", 
        .root_source_file = .{ .path = "src/main.zig" }, 
        .optimize = optimize, 
        .target = target
    });

    rl.link(b, exe, target, optimize);
    exe.addModule("raylib", raylib);
    exe.addModule("raylib-math", raylib_math);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run ++party");
    run_step.dependOn(&run_cmd.step);

    b.installArtifact(exe);
}

