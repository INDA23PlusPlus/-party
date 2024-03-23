const std = @import("std");
const ecs = @import("ecs.zig");

fn gravity(world: *ecs.World) !void {
    var query = world.query(&.{ecs.Mover}, &.{});
    while (query.next()) |_| {
        var mover = try query.get(ecs.Mover);

        mover.velocity_y -= 9.82;
    }
}

fn move(world: *ecs.World) !void {
    var query = world.query(&.{ ecs.Position, ecs.Mover }, &.{});
    while (query.next()) |_| {
        var position = try query.get(ecs.Position);
        const mover = try query.get(ecs.Mover);

        position.x += std.math.lossyCast(i32, mover.velocity_x);
        position.y += std.math.lossyCast(i32, mover.velocity_y);
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

test "run" {
    var buffer: ecs.Buffer = undefined;
    var world = ecs.World.init(&buffer);

    var timer = try std.time.Timer.start();

    for (0..ecs.N) |i| {
        const position = ecs.Position{
            .x = @intCast(i),
            .y = @intCast(i),
        };
        const mover = ecs.Mover{
            .subpixel_x = 0.0,
            .subpixel_y = 0.0,
            .velocity_x = @floatFromInt(i),
            .velocity_y = @floatFromInt(i),
            .acceleration_x = 0.0,
            .acceleration_y = 0.0,
        };
        const collider = ecs.Collider{};
        const texture = ecs.Texture{};
        _ = try world.build(.{ position, mover, collider, texture });
    }

    std.log.warn("{}", .{timer.lap() / 1000000000});

    for (0..1000) |_| {
        try gravity(&world);
        try move(&world);
        try render(&world);
    }

    std.log.warn("{}", .{timer.read() / 1000000000});
}
