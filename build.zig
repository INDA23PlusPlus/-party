const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib-zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raylib_math = raylib_dep.module("raylib-math"); // raymath module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library


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

    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raylib-math", raylib_math);

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

    tests.root_module.addImport("raylib", raylib);
    tests.root_module.addImport("raylib-math", raylib_math);

    const run_tests_cmd = b.addRunArtifact(tests);
    const run_tests_step = b.step("test", "Run tests");
    run_tests_step.dependOn(&run_tests_cmd.step);
}
