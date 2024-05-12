const std = @import("std");
const rl = @import("raylib-zig/build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const raylib = rl.getModule(b, "raylib-zig");
    const raylib_math = rl.math.getModule(b, "raylib-zig");
    const xev = b.dependency("libxev", .{ .target = target, .optimize = optimize });

    // Nobody cares about emscripten
    // if (target.result.os.tag == .emscripten) {
    //     const exe_lib = rl.compileForEmscripten(b, "++party", "src/main.zig", target, optimize);
    //     exe_lib.root_module.addImport("raylib", raylib);
    //     exe_lib.root_module.addImport("raylib-math", raylib_math);
    //     const raylib_artifact = rl.getRaylib(b, target, optimize);
    //     exe_lib.linkLibrary(raylib_artifact);
    //     const link_step = try rl.linkWithEmscripten(b, &[_]*std.Build.Step.Compile{ exe_lib, raylib_artifact });
    //     b.getInstallStep().dependOn(&link_step.step);
    //     const run_step = try rl.emscriptenRunStep(b);
    //     run_step.step.dependOn(&link_step.step);
    //     const run_option = b.step("run", "Run ++party");
    //     run_option.dependOn(&run_step.step);
    //     return;
    // }

    // const text_tool = b.addExecutable(.{
    //     .name = "text_tool",
    //     .root_source_file = .{ .path = "src/text_tool.zig" },
    //     .optimize = optimize,
    //     .target = target,
    // });
    // const text_tool_cmd = b.addRunArtifact(text_tool);
    // if (b.args) |args| {
    //     text_tool_cmd.addArgs(args);
    // }
    // const text_tool_step = b.step("tool", "Run text_tool");
    // text_tool_step.dependOn(&text_tool_cmd.step);
    // b.installArtifact(text_tool);

    const exe = b.addExecutable(.{
        .name = "++party",
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = optimize,
        .target = target,
    });

    rl.link(b, exe, target, optimize);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raylib-math", raylib_math);
    exe.root_module.addImport("xev", xev.module("xev"));

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addArg("local");
    run_cmd.addArg("--wasd");
    run_cmd.addArg("--ijkl");
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run ++party in local (default) mode");
    run_step.dependOn(&run_cmd.step);

    const run_server_cmd = b.addRunArtifact(exe);
    run_server_cmd.addArg("server");
    if (b.args) |args| {
        run_server_cmd.addArgs(args);
    }
    const run_server_step = b.step("run-server", "Run ++party in server mode");
    run_server_step.dependOn(&run_server_cmd.step);

    const run_client_cmd = b.addRunArtifact(exe);
    run_client_cmd.addArg("client");
    if (b.args) |args| {
        run_client_cmd.addArgs(args);
    }
    const run_client_step = b.step("run-client", "Run ++party in client mode");
    run_client_step.dependOn(&run_client_cmd.step);

    b.installArtifact(exe);

    const tests = b.addTest(.{
        .name = "tests",
        .root_source_file = .{ .path = "src/test.zig" },
        .target = target,
        .optimize = optimize,
    });

    rl.link(b, tests, target, optimize);
    tests.root_module.addImport("raylib", raylib);
    tests.root_module.addImport("raylib-math", raylib_math);
    tests.root_module.addImport("xev", xev.module("xev"));

    const run_tests_cmd = b.addRunArtifact(tests);
    const run_tests_step = b.step("test", "Run tests");
    run_tests_step.dependOn(&run_tests_cmd.step);
}
