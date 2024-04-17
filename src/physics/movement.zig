const std = @import("std");
const ecs = @import("../ecs/ecs.zig");
const collision = @import("collision.zig");

/// Moves entities.
/// Entities with Pos and Mov components, and lacking a Col component, are moved without collision detection.
/// Entities with Pos, Mov, and Col components are moved so they never overlap; if a collision occurs, it is added to the collision queue.
/// Collidable entities occypying the same space are unable to move.
pub fn update(world: *ecs.world.World, collisions: *collision.CollisionQueue, allocator: std.mem.Allocator) !void {
    try updateVelocity(world);
    try updateIncorporeal(world);
    try updateCorporeal(world, collisions, allocator);
}

pub fn updateVelocity(world: *ecs.world.World) !void {
    var query = world.query(&.{ecs.component.Mov}, &.{});

    while (query.next()) |_| {
        const mov = query.get(ecs.component.Mov) catch unreachable;
        mov.velocity = mov.velocity.add(mov.acceleration);
        // We should not reset acceleration.
        // Instantaneous movements should be handled using velocities.
    }
}

pub fn updateIncorporeal(world: *ecs.world.World) !void {
    var query = world.query(&.{
        ecs.component.Pos,
        ecs.component.Mov,
    }, &.{
        ecs.component.Col,
    });

    while (query.next()) |_| {
        const pos = query.get(ecs.component.Pos) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;

        mov.subpixel = mov.subpixel.add(mov.velocity);

        const reposition = mov.subpixel.integerParts().toInts();

        pos.pos += reposition;
        mov.subpixel = mov.subpixel.sub(reposition);
    }
}

pub fn updateCorporeal(world: *ecs.world.World, collisions: *collision.CollisionQueue, allocator: std.mem.Allocator) !void {
    var query = world.query(&.{
        ecs.component.Pos,
        ecs.component.Col,
        ecs.component.Mov,
    }, &.{});

    while (query.next()) |entity| {
        const pos = query.get(ecs.component.Pos) catch unreachable;
        const col = query.get(ecs.component.Col) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;

        mov.subpixel = mov.subpixel.add(mov.velocity);

        const reposition_i16: @Vector(2, i16) = mov.subpixel.integerParts().toInts();

        if (@reduce(.And, reposition_i16 == @Vector(2, i32){ 0, 0 })) {
            continue;
        }

        mov.subpixel = mov.subpixel.sub(reposition_i16);

        var reposition: @Vector(2, i32) = reposition_i16;

        while (@reduce(.Or, reposition != @Vector(2, i32){ 0, 0 })) {
            const u: @Vector(2, i32) = @intFromBool(reposition > @Vector(2, i32){ 0, 0 });
            const v: @Vector(2, i32) = @intFromBool(reposition < @Vector(2, i32){ 0, 0 });
            const velocity = u - v;

            const collide = try collision.checkCollisions(
                entity,
                pos,
                col,
                velocity,
                world,
                collisions,
                allocator,
            );

            if (collide.xy) {
                const cause: @Vector(2, i32) = [_]i32{ @intFromBool(!collide.x), @intFromBool(!collide.y) };
                const corner: @Vector(2, i32) = @splat(@intFromBool(collide.x or collide.y));

                const swapped = @shuffle(i32, reposition, undefined, @Vector(2, i32){ 1, 0 });
                const largest = @intFromBool(reposition > swapped);

                reposition *= cause & (corner | largest);
            } else {
                pos.pos += velocity;
                reposition -= velocity;
            }
        }
    }
}
