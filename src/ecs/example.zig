const std = @import("std");
const ecs = @import("ecs.zig");

// EXAMPLE 1

fn gravity(world: *ecs.World) !void {
    var query = world.query(&.{ecs.Mover}, &.{});
    while (query.next()) |_| {
        var mover = try query.get(ecs.Mover);

        mover.velocity_y -= 1.0;
    }
}

fn move(world: *ecs.World) !void {
    var query = world.query(&.{ ecs.Position, ecs.Mover }, &.{});
    while (query.next()) |_| {
        var position = try query.get(ecs.Position);
        const mover = try query.get(ecs.Mover);

        position.x += std.math.lossyCast(i32, mover.velocity_x);
        position.y += std.math.lossyCast(i32, mover.velocity_y);

        if (position.y <= 0) {
            position.y = 0;
        }
    }
}

fn render(world: *ecs.World) !void {
    var query = world.query(&.{ ecs.Position, ecs.Texture }, &.{});
    while (query.next()) |_| {
        const position = try query.get(ecs.Position);
        const texture = try query.get(ecs.Texture);

        _ = position;
        _ = texture;

        // draw_texture()
    }

    // render_image()
}

inline fn buffered_writer(underlying_stream: anytype) std.io.BufferedWriter(10000, @TypeOf(underlying_stream)) {
    return .{ .unbuffered_writer = underlying_stream };
}

test {
    std.log.warn("", .{});

    var buffer: ecs.Buffer = undefined;
    var world = ecs.World.init(&buffer);

    var timer = try std.time.Timer.start();

    for (0..5) |i| {
        const position = ecs.Position{
            .x = @intCast(i),
            .y = @intCast(i),
        };
        const mover = ecs.Mover{
            .velocity_x = @floatFromInt(i),
            .velocity_y = @floatFromInt(i),
        };
        const collider = ecs.Collider{};
        const texture = ecs.Texture{};
        _ = try world.build(.{ position, mover, collider, texture });
    }

    std.log.warn("{}", .{timer.lap() / std.time.ns_per_ms});

    const iterations = 10;
    for (0..iterations) |_| {
        try gravity(&world);
        try move(&world);
        try render(&world);
    }

    std.log.warn("{}", .{timer.read() / (iterations * std.time.ns_per_ms)});
}

// EXAMPLE 2

test "throw_ballz" {
    std.log.warn("", .{});
    var writer = buffered_writer(std.io.getStdOut().writer());
    var w = writer.writer();

    var buffer: ecs.Buffer = undefined;
    var world = ecs.World.init(&buffer);

    // Create ballz, launching them with various velocities.
    for (0..10) |i| {
        const position = ecs.Position{};
        const mover = ecs.Mover{
            .velocity_x = @floatFromInt(i),
            .velocity_y = @floatFromInt(i),
        };

        try printEntity(i, position.x, position.y, mover.velocity_x, mover.velocity_y, &w);

        _ = try world.build(.{ position, mover });
    }

    // Simulate 10 frames.
    for (0..10) |_| {
        var gravity_query = world.query(&.{ecs.Mover}, &.{});
        while (gravity_query.next()) |_| {
            var mover = try gravity_query.get(ecs.Mover);

            mover.velocity_y -= 1.0;
        }
    }
}

fn printEntity(i: usize, px: i32, py: i32, vx: f32, vy: f32, w: anytype) !void {
    try w.print("entity {}:\n - {} {}\n - {} {}", .{ i, px, py, vx, vy });
}
