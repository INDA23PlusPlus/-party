const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const render = @import("../render.zig");
const movement = @import("../physics/movement.zig");
const collision = @import("../physics/collision.zig");
const animator = @import("../animation/animator.zig");
const constants = @import("../constants.zig");
const input = @import("../input.zig");
const Animation = @import("../animation/animations.zig").Animation;
const AssetManager = @import("../AssetManager.zig");
const Invariables = @import("../Invariables.zig");

const left_texture_offset = [_]i32{ -5, -10 };
const right_texture_offset = [_]i32{ -21, -10 };

const ground_speed = ecs.component.F32.init(5, 3);
const ground_acceleration = ecs.component.F32.init(1, 6);
const ground_deceleration = ecs.component.F32.init(1, 3);
const ground_friction = ecs.component.F32.init(1, 3);

const air_speed = ecs.component.F32.init(2, 1);
const air_acceleration = ecs.component.F32.init(1, 12);
const air_deceleration = ecs.component.F32.init(1, 8);
const air_friction = ecs.component.F32.init(1, 4);

const jump_strength = ecs.component.F32.init(-7, 2);
const jump_gravity = ecs.component.F32.init(1, 8);
const fall_gravity = ecs.component.Vec2.init(0, ecs.component.F32.init(2, 5));
const fall_speed = ecs.component.Vec2.init(0, ecs.component.F32.init(4, 1));

const bounce_strength = ecs.component.F32.init(3, 2);
const attack_strength = ecs.component.F32.init(5, 1);

pub fn init(sim: *simulation.Simulation, _: input.Timeline) !void {
    sim.meta.minigame_ticks_per_update = 16;

    // Background
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{},
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/smash_background_0.png"),
            .w = 32,
            .h = 18,
        },
    });
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{},
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/smash_background_1.png"),
            .w = 32,
            .h = 18,
        },
    });
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{},
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/smash_background_2.png"),
            .w = 32,
            .h = 18,
        },
    });

    // Platform
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = [_]i32{ 16 * 6, 16 * 15 } },
        ecs.component.Col{ .dim = [_]i32{ 16 * 20, 16 * 3 } },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/smash_platform.png"),
            .w = 20,
            .h = 3,
            .v = 2,
        },
    });

    // Players
    for (0..constants.max_player_count) |i| {
        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = @intCast(i) },
            ecs.component.Pos{ .pos = [_]i32{ 128 + 16 * @as(i32, @intCast(i)), 232 } },
            ecs.component.Col{ .dim = [_]i32{ 6, 6 } },
            ecs.component.Mov{},
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/smash_cat.png"),
                .w = 2,
                .subpos = right_texture_offset,
                .tint = constants.player_colors[i],
            },
            ecs.component.Anm{ .animation = Animation.SmashIdle, .interval = 8, .looping = true },
            ecs.component.Dir{ .facing = .None },
            ecs.component.Ctr{
                .counter = 100,
            }, // For input buffering the jump action and for implementing coyote time.
        });
    }

    // Global Knockback Strength
    _ = try sim.world.spawn(&.{ecs.component.Ctr});
}

pub fn update(sim: *simulation.Simulation, timeline: input.Timeline, rt: Invariables) !void {
    var collisions = collision.CollisionQueue.init(rt.arena) catch @panic("collision");
    const inputs = timeline.latest();

    inputSystem(&sim.world, &inputs);
    gravitySystem(&sim.world);

    movement.update(&sim.world, &collisions, rt.arena) catch @panic("movement");

    resolveCollisions(&sim.world, &collisions);
    airborneSystem(&sim.world);
    movementSystem(&sim.world);
    animationSystem(&sim.world);

    animator.update(&sim.world);
}

fn inputSystem(world: *ecs.world.World, inputs: *const input.AllPlayerButtons) void {
    var query = world.query(&.{
        ecs.component.Plr,
        ecs.component.Mov,
        ecs.component.Tex,
        ecs.component.Ctr,
        ecs.component.Dir,
    }, &.{});

    while (query.next()) |entity| {
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;
        const tex = query.get(ecs.component.Tex) catch unreachable;
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        const dir = query.get(ecs.component.Dir) catch unreachable;

        const state = inputs[plr.id];
        if (state.is_connected()) {
            if (state.dpad == .West) {
                if (state.dpad == .North) {
                    dir.facing = .Northwest;
                } else if (state.dpad == .South) {
                    dir.facing = .Southwest;
                } else {
                    dir.facing = .West;
                }

                if (mov.velocity.vector[0] < 0) {
                    tex.flip_horizontal = true;
                    tex.subpos = left_texture_offset;
                }
            } else if (state.dpad == .East) {
                if (state.dpad == .North) {
                    dir.facing = .Northeast;
                } else if (state.dpad == .South) {
                    dir.facing = .Southeast;
                } else {
                    dir.facing = .East;
                }

                if (mov.velocity.vector[0] > 0) {
                    tex.flip_horizontal = false;
                    tex.subpos = right_texture_offset;
                }
            } else {
                if (state.dpad == .North) {
                    dir.facing = .North;
                } else if (state.dpad == .South) {
                    dir.facing = .South;
                } else {
                    dir.facing = .None;
                }
            }

            if (state.button_a == .Pressed and world.checkSignature(entity, &.{}, &.{ecs.component.Jmp})) blk: {
                // Coyote time
                if (ctr.counter > 5 and world.checkSignature(entity, &.{ecs.component.Air}, &.{})) break :blk;

                mov.velocity.vector[1] = jump_strength.bits;
                world.promote(entity, &.{ecs.component.Jmp});
            }

            if (state.button_a == .Pressed) ctr.counter = 0;

            if ((!state.button_a.is_down() or mov.velocity.vector[1] > 0) and world.checkSignature(entity, &.{ecs.component.Jmp}, &.{})) {
                world.demote(entity, &.{ecs.component.Jmp});
            }
        }
    }
}

fn animationSystem(world: *ecs.world.World) void {
    var query = world.query(&.{
        ecs.component.Plr,
        ecs.component.Mov,
        ecs.component.Anm,
        ecs.component.Dir,
    }, &.{});

    while (query.next()) |entity| {
        const mov = query.get(ecs.component.Mov) catch unreachable;
        const anm = query.get(ecs.component.Anm) catch unreachable;
        const dir = query.get(ecs.component.Dir) catch unreachable;

        const previous = anm.animation;

        const moving = mov.velocity.vector[0] != 0 and switch (dir.facing) {
            .None, .North, .South => false,
            else => true,
        };
        const jumping = world.checkSignature(entity, &.{ecs.component.Jmp}, &.{});
        const airborne = world.checkSignature(entity, &.{ecs.component.Air}, &.{});
        const falling = !jumping and airborne and mov.velocity.vector[1] > 0;

        if (moving) anm.animation = .SmashRun else anm.animation = .SmashIdle;

        if (jumping) {
            anm.looping = false;
            anm.animation = .SmashJump;
            if (anm.subframe == 0) anm.interval = 1 else anm.interval = 8;
        } else if (falling) {
            anm.looping = false;
            anm.animation = .SmashFall;
        } else {
            anm.looping = true;
        }

        if (anm.animation != previous) anm.subframe = 0;
    }
}

fn movementSystem(world: *ecs.world.World) void {
    var query_grounded = world.query(&.{
        ecs.component.Mov,
        ecs.component.Dir,
    }, &.{
        ecs.component.Air,
    });

    while (query_grounded.next()) |_| {
        const mov = query_grounded.get(ecs.component.Mov) catch unreachable;
        const dir = query_grounded.get(ecs.component.Dir) catch unreachable;

        const target = switch (dir.facing) {
            .Northwest, .Southwest, .West => ground_speed.mul(-1),
            .Northeast, .Southeast, .East => ground_speed,
            else => ecs.component.F32.init(0, 1),
        };

        const difference = target.sub(mov.velocity.x());

        const rate = if (target.abs().cmp(ecs.component.F32.init(1, 10), .gt)) ground_acceleration else ground_deceleration;

        const sign = @as(i16, @intFromBool(difference.bits > 0)) - @intFromBool(difference.bits < 0);

        const amount = difference.abs().mul(rate).mul(sign);

        mov.velocity.vector[0] += amount.bits;

        if (@abs(mov.velocity.vector[0]) < 10) mov.velocity.vector[0] = 0;

        // std.debug.print("target: {}\ndifference: {}\nrate: {}\nsign: {}\namount: {}\n", .{ target, difference, rate, sign, amount });

        // mov.velocity.vector[0] = @max(@min(mov.velocity.vector[0], ground_speed.bits), -ground_speed.bits);

        // if (mov.velocity.vector[0] > 0) {
        //     mov.velocity.vector[0] = @max(mov.velocity.vector[0] - ground_friction.bits, 0);
        // } else if (mov.velocity.vector[0] < 0) {
        //     mov.velocity.vector[0] = @min(mov.velocity.vector[0] + ground_friction.bits, 0);
        // } else {
        //     mov.velocity.vector[0] = 0;
        // }
    }

    var query_airborne = world.query(&.{
        ecs.component.Mov,
        ecs.component.Dir,
        ecs.component.Air,
    }, &.{});

    while (query_airborne.next()) |_| {
        const mov = query_airborne.get(ecs.component.Mov) catch unreachable;
        const dir = query_airborne.get(ecs.component.Dir) catch unreachable;

        const target = switch (dir.facing) {
            .Northwest, .Southwest, .West => air_speed.mul(-1),
            .Northeast, .Southeast, .East => air_speed,
            else => ecs.component.F32.init(0, 1),
        };

        const difference = target.sub(mov.velocity.x());

        const rate = if (target.abs().cmp(ecs.component.F32.init(1, 10), .gt)) air_acceleration else air_deceleration;

        const sign = @as(i16, @intFromBool(difference.bits > 0)) - @intFromBool(difference.bits < 0);

        const amount = difference.abs().mul(rate).mul(sign);

        mov.velocity.vector[0] += amount.bits;

        if (@abs(mov.velocity.vector[0]) < 10) mov.velocity.vector[0] = 0;

        // switch (dir.facing) {
        //     .Northwest, .Southwest, .West => mov.velocity.vector[0] -= air_acceleration.bits,
        //     .Northeast, .Southeast, .East => mov.velocity.vector[0] += air_acceleration.bits,
        //     else => {},
        // }

        // mov.velocity.vector = @max(@min(mov.velocity.vector, max_air_velocity.vector), -max_air_velocity.vector);

        // if (mov.velocity.vector[0] > 0) {
        //     mov.velocity.vector[0] = @max(mov.velocity.vector[0] - air_friction.bits, 0);
        // } else if (mov.velocity.vector[0] < 0) {
        //     mov.velocity.vector[0] = @min(mov.velocity.vector[0] + air_friction.bits, 0);
        // } else {
        //     mov.velocity.vector[0] = 0;
        // }
    }
}

fn gravitySystem(world: *ecs.world.World) void {
    var query_jumping = world.query(&.{
        ecs.component.Mov,
        ecs.component.Air,
        ecs.component.Jmp,
    }, &.{});

    while (query_jumping.next()) |_| {
        const mov = query_jumping.get(ecs.component.Mov) catch unreachable;

        mov.velocity.vector[1] += jump_gravity.bits;
    }

    var query_falling = world.query(&.{
        ecs.component.Mov,
        ecs.component.Air,
    }, &.{
        ecs.component.Jmp,
    });

    while (query_falling.next()) |_| {
        const mov = query_falling.get(ecs.component.Mov) catch unreachable;

        mov.velocity = mov.velocity.add(fall_gravity);

        mov.velocity.vector[1] = @min(fall_speed.vector[1], mov.velocity.vector[1]);
    }
}

fn airborneSystem(world: *ecs.world.World) void {
    var query_airborne = world.query(&.{
        ecs.component.Plr,
        ecs.component.Pos,
        ecs.component.Mov,
        ecs.component.Col,
        ecs.component.Air,
        ecs.component.Ctr,
    }, &.{});

    while (query_airborne.next()) |ent1| {
        const ctr1 = query_airborne.get(ecs.component.Ctr) catch unreachable;

        ctr1.counter += 1;

        var query = world.query(&.{
            ecs.component.Pos,
            ecs.component.Col,
        }, &.{});

        while (query.next()) |ent2| {
            if (ent1.eq(ent2)) continue;

            const pos1 = query_airborne.get(ecs.component.Pos) catch unreachable;
            const col1 = query_airborne.get(ecs.component.Col) catch unreachable;
            const pos2 = query.get(ecs.component.Pos) catch unreachable;
            const col2 = query.get(ecs.component.Col) catch unreachable;

            if (world.checkSignature(ent2, &.{}, &.{ecs.component.Plr}) and collision.intersectsAt(pos1, col1, pos2, col2, [_]i32{ 0, 1 })) {
                // Scuffed input buffering. Highly fragile because we use the same counter for coyote time.
                if (ctr1.counter < 8 and world.checkSignature(ent1, &.{}, &.{ecs.component.Jmp})) {
                    world.promote(ent1, &.{ecs.component.Jmp});
                    const mov1 = query_airborne.get(ecs.component.Mov) catch unreachable;
                    mov1.velocity.vector[1] = jump_strength.bits;
                } else {
                    world.demote(ent1, &.{ecs.component.Air});
                    ctr1.counter = 0;
                }
                break;
            }
        }
    }

    var query_grounded = world.query(&.{
        ecs.component.Plr,
        ecs.component.Pos,
        ecs.component.Mov,
        ecs.component.Col,
        ecs.component.Ctr,
    }, &.{
        ecs.component.Air,
    });

    while (query_grounded.next()) |ent1| {
        const mov1 = query_grounded.get(ecs.component.Mov) catch unreachable;

        if (mov1.velocity.vector[1] > 0) mov1.velocity.vector[1] = 0;

        var query = world.query(&.{
            ecs.component.Pos,
            ecs.component.Col,
        }, &.{});

        var airborne = true;

        while (query.next()) |ent2| {
            if (ent1.eq(ent2)) continue;

            const pos1 = query_grounded.get(ecs.component.Pos) catch unreachable;
            const col1 = query_grounded.get(ecs.component.Col) catch unreachable;
            const pos2 = query.get(ecs.component.Pos) catch unreachable;
            const col2 = query.get(ecs.component.Col) catch unreachable;

            if (collision.intersectsAt(pos1, col1, pos2, col2, [_]i32{ 0, 1 })) {
                airborne = false;
                break;
            }
        }

        if (airborne) world.promote(ent1, &.{ecs.component.Air});
    }
}

fn resolveCollisions(world: *ecs.world.World, collisions: *collision.CollisionQueue) void {
    for (collisions.collisions.keys()) |c| {
        const plrposmov1 = world.checkSignature(c.a, &.{
            ecs.component.Plr,
            ecs.component.Mov,
            ecs.component.Pos,
        }, &.{});
        const plrposmov2 = world.checkSignature(c.b, &.{
            ecs.component.Plr,
            ecs.component.Mov,
            ecs.component.Pos,
        }, &.{});

        if (plrposmov1 and plrposmov2) {
            const pos1 = world.inspect(c.a, ecs.component.Pos) catch unreachable;
            const pos2 = world.inspect(c.b, ecs.component.Pos) catch unreachable;
            const mov1 = world.inspect(c.a, ecs.component.Mov) catch unreachable;
            const mov2 = world.inspect(c.b, ecs.component.Mov) catch unreachable;

            const left: i16 = @intFromBool(pos1.pos[0] < pos2.pos[0]);
            const right: i16 = @intFromBool(pos1.pos[0] > pos2.pos[0]);
            const middle: i16 = @intFromBool(pos1.pos[0] == pos2.pos[0]);
            const top: i16 = @intFromBool(pos1.pos[1] < pos2.pos[1]);
            const bottom: i16 = @intFromBool(pos1.pos[1] > pos2.pos[1]);

            const leftright = (right - left);
            const topbottom = (bottom - top);

            const direction = leftright + middle * topbottom;
            const bounce = bounce_strength.mul(direction);

            mov1.velocity.vector[0] += bounce.bits;
            mov2.velocity.vector[0] -= bounce.bits;
        }
    }
}
