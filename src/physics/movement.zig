const std = @import("std");
const ecs = @import("../ecs/ecs.zig");
const collision = @import("collision.zig");

/// Moves entities.
/// Entities with Pos and Mov components, and lacking a Col component, are moved without collision detection.
/// Entities with Pos, Mov, and Col components are moved so they never overlap; if a collision occurs, it is added to the collision queue.
/// Collidable entities occypying the same space are unable to move.
pub fn update(world: *ecs.world.World, collisions: *collision.CollisionQueue) !void {
    try updateIncorporeal(world);
    try updateCorporeal(world, collisions);
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
        mov.velocity = mov.velocity.add(mov.acceleration);
        mov.acceleration = ecs.component.Vec2.init(0, 0);
        mov.subpixel = mov.subpixel.add(mov.velocity);
        const reposition = mov.subpixel.integerParts().toInts();
        pos.pos += reposition;
        mov.subpixel = mov.subpixel.sub(reposition);
    }
}

pub fn updateCorporeal(world: *ecs.world.World, collisions: *collision.CollisionQueue) !void {
    var query = world.query(&.{
        ecs.component.Pos,
        ecs.component.Col,
        ecs.component.Mov,
    }, &.{});

    while (query.next()) |entity| {
        const pos = query.get(ecs.component.Pos) catch unreachable;
        const col = query.get(ecs.component.Col) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;

        mov.velocity = mov.velocity.add(mov.acceleration);
        mov.acceleration = ecs.component.Vec2.init(0, 0);
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

// const Benchmarker = struct {
//     const Self = @This();

//     time: u64,
//     laps: u64,
//     timer: ?std.time.Timer,

//     pub fn init() Self {
//         return Self{
//             .time = 0,
//             .laps = 0,
//             .timer = null,
//         };
//     }

//     pub fn start(self: *Self) !void {
//         self.timer = try std.time.Timer.start();
//     }

//     pub fn reset(self: *Self) !void {
//         var timer = &self.timer orelse return error{};

//         self.time = 0;
//         self.laps = 0;
//         timer.reset();
//     }

//     pub fn lap(self: *Self) !void {
//         var timer = &self.timer orelse return error{};

//         self.time += timer.lap();
//         self.laps += 1;
//     }

//     pub fn write(self: *Self) !void {
//         if (self.laps == 0) return error{};

//         var out = std.io.getStdOut();
//         var writer = out.writer();

//         const ns_per_lap = self.time / self.laps;
//         const ms_per_lap = ns_per_lap / std.time.ns_per_ms;
//         try writer.print("{d:>.4}G ms/lap \n", .{ms_per_lap});

//         const laps_per_ns = self.laps / self.time;
//         const laps_per_ms = laps_per_ns * std.time.ns_per_ms;
//         try writer.print("{d:>.4}G laps/ms \n", .{laps_per_ms});

//         const frames_per_lap = ms_per_lap / 17.0;
//         try writer.print("{d:>.4}G frames/lap \n", .{frames_per_lap});

//         const laps_per_frame = laps_per_ms * 17.0;

//         try writer.print("{d:>.4}G laps/frame \n", .{laps_per_frame});
//     }
// };
