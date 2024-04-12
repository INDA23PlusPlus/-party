const ecs = @import("ecs.zig");
const std = @import("std");

test "spawn_promote_demote_kill" {
    var world = ecs.world.World{};
    const entity = try world.spawn(&.{ecs.component.Pos});

    try std.testing.expect(entity.identifier == 0 and entity.generation == 0);

    world.promote(entity, &.{ecs.component.Mov});
    world.demote(entity, &.{ecs.component.Mov});
    world.kill(entity);
}

test "spawn_limit" {
    var world = ecs.world.World{};

    for (0..ecs.world.N) |_| {
        _ = try world.spawn(&.{});
    }

    try std.testing.expect(world.spawn(&.{}) == ecs.world.WorldError.SpawnLimitExceeded);
}

test "reset" {
    var world = ecs.world.World{};

    for (0..ecs.world.N) |_| {
        _ = try world.spawn(&.{ ecs.component.Pos, ecs.component.Mov });
    }

    var query1 = world.query(&.{ecs.component.Pos}, &.{});
    while (query1.next()) |_| {
        const pos = try query1.get(ecs.component.Pos);
        if (!(pos.pos[0] == 0 and pos.pos[1] == 0)) {
            unreachable;
        }
    }

    // try accelerate(&world);
    // try move(&world);

    world.reset();

    for (0..ecs.world.N / 2) |_| {
        _ = try world.spawn(&.{ ecs.component.Pos, ecs.component.Mov });
    }

    var query2 = world.query(&.{ecs.component.Pos}, &.{});
    while (query2.next()) |_| {
        const pos = try query2.get(ecs.component.Pos);
        if (!(pos.pos[0] == 0 and pos.pos[1] == 0)) {
            unreachable;
        }
    }

    // try accelerate(&world);
    // try move(&world);
}

test "build entities" {
    var world = ecs.world.World{};

    for (0..ecs.world.N) |i| {
        const j: i32 = @intCast(i);
        const col = ecs.component.Col{};
        const pos = ecs.component.Pos{ .pos = @splat(j) };
        _ = try world.spawnWith(.{ pos, col });
    }
}
