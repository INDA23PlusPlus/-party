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

// TODO: Merge and use new input system
// TODO: Use input for movement and `Dir` for attack direction and animation
// TODO: Attack animation and effect
// TODO: Knockback increase over time
// TODO: Blocking action, animation and effect

const left_texture_offset = [_]i32{ -5, -10 };
const right_texture_offset = [_]i32{ -21, -10 };
const redness_increase_frames = 30;

const ground_speed = ecs.component.F32.init(4, 3);
const ground_acceleration = ecs.component.F32.init(1, 6);
const ground_deceleration = ecs.component.F32.init(1, 3);
const ground_friction = ecs.component.F32.init(1, 10);

const air_speed = ecs.component.F32.init(5, 3);
const air_acceleration = ecs.component.F32.init(1, 10);
const air_deceleration = ecs.component.F32.init(1, 10);
const air_friction = ecs.component.F32.init(1, 20);

const jump_strength = ecs.component.F32.init(-5, 2);
const jump_gravity = ecs.component.F32.init(1, 12);
const jump_buffer = 6;
const coyote_time = 8;

const fall_gravity = ecs.component.Vec2.init(0, ecs.component.F32.init(1, 4));
const fall_speed = ecs.component.Vec2.init(0, ecs.component.F32.init(4, 1));

const hitstun = 10;
const bounce_strength = ecs.component.F32.init(3, 2);

const attack_strength_small = ecs.component.F32.init(2, 1);
const attack_strength_medium = ecs.component.F32.init(4, 1);
const attack_strength_large = ecs.component.F32.init(5, 1);
const attack_cooldown = 20;
const attack_buffer = 5;
const attack_dimensions = [_]i32{ 16, 16 };
const attack_ticks = 7;
const attack_player_offset = [_]i32{ -5, -5 };
const attack_directional_offset = 16;

// var benchmarker: @import("../Benchmarker.zig") = undefined;
pub fn init(sim: *simulation.Simulation, _: input.Timeline) !void {
    // benchmarker = @import("../Benchmarker.zig").init("smash") catch @panic("");

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
        ecs.component.Col{
            .dim = [_]i32{ 16 * 20, 16 * 3 },
            .layer = collision.Layer{ .base = false, .platform = true },
            .mask = collision.Layer{ .base = false, .player = true },
        },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/smash_platform.png"),
            .w = 20,
            .h = 3,
            .v = 2,
        },
    });

    // Players
    for (0..2) |i| {
        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = @intCast(i) },
            ecs.component.Pos{ .pos = [_]i32{ 128 + 16 * @as(i32, @intCast(i)), 234 } },
            ecs.component.Col{
                .dim = [_]i32{ 6, 6 },
                .layer = collision.Layer{ .base = false, .player = true },
                .mask = collision.Layer{ .base = false, .platform = true, .player = true },
            },
            ecs.component.Mov{},
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/smash_cat.png"),
                .w = 2,
                .subpos = right_texture_offset,
                .tint = constants.player_colors[i],
            },
            ecs.component.Anm{ .animation = Animation.SmashIdle, .interval = 8, .looping = true },
            ecs.component.Tmr{}, // Coyote timer and hit recovery timer
            ecs.component.Ctr{}, // Attack timer and block timer
        });
    }
}

pub fn update(sim: *simulation.Simulation, timeline: input.Timeline, rt: Invariables) !void {
    // TEMPORARY
    if (rl.isKeyPressed(rl.KeyboardKey.key_r)) {
        sim.world.reset();
        try init(sim, timeline);
    }

    const inputs = &timeline.latest();

    var collisions = collision.CollisionQueue.init(rt.arena) catch @panic("collision");

    try actionSystem(sim, timeline); // 30 laps/ms
    try attackSystem(&sim.world, inputs); // 100 laps/ms

    gravitySystem(&sim.world); // 150 laps/ms
    movement.update(&sim.world, &collisions, rt.arena) catch @panic("movement"); // 70 laps/ms
    resolveCollisions(&sim.world, &collisions); // 400 laps/ms
    airborneSystem(&sim.world); // 70 laps/ms
    forceSystem(&sim.world, inputs); // 120 laps/ms

    deathSystem(sim); // 200 laps/ms

    animationSystem(&sim.world, inputs); // 150 laps/ms
    animator.update(&sim.world); // 160 laps/ms
    particleSystem(&sim.world); // 250 laps/ms
    backgroundColorSystem(sim); // 650 laps/ms
}

fn backgroundColorSystem(sim: *simulation.Simulation) void {
    if (sim.meta.ticks_elapsed % redness_increase_frames != 0) return;

    var query = sim.world.query(&.{
        ecs.component.Tex,
    }, &.{
        ecs.component.Plr,
    });

    while (query.next()) |_| {
        const tex = query.get(ecs.component.Tex) catch unreachable;

        tex.tint.b = @max(100, tex.tint.b - 1);
        tex.tint.g = @max(100, tex.tint.g - 1);
    }
}

fn actionSystem(sim: *simulation.Simulation, timeline: input.Timeline) !void {
    var query = sim.world.query(&.{
        ecs.component.Plr,
        ecs.component.Pos,
        ecs.component.Mov,
        ecs.component.Tmr,
        ecs.component.Ctr,
    }, &.{});

    while (query.next()) |entity| {
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const pos = query.get(ecs.component.Pos) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;
        const tmr = query.get(ecs.component.Tmr) catch unreachable;
        const ctr = query.get(ecs.component.Ctr) catch unreachable;

        const state = timeline.latest()[plr.id];

        const grounded = sim.world.checkSignature(entity, &.{}, &.{ecs.component.Air});
        const not_jumping = sim.world.checkSignature(entity, &.{}, &.{ecs.component.Jmp});
        const wants_jump = state.button_a == .Pressed or (if (timeline.buttonStateTick(plr.id, .a, .Pressed)) |press_tick| sim.meta.ticks_elapsed - press_tick < jump_buffer else false);
        const can_jump = not_jumping and (grounded or tmr.ticks < coyote_time);

        if (wants_jump and can_jump) {
            mov.velocity.vector[1] = jump_strength.bits;
            sim.world.promote(entity, &.{ecs.component.Jmp});
            tmr.ticks = coyote_time;

            _ = try sim.world.spawnWith(.{
                pos.*,
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/smash_jump_smoke.png"),
                    .subpos = [_]i32{ -14, -26 },
                    .w = 2,
                    .h = 2,
                    .tint = rl.Color.init(100, 100, 100, 100),
                },
                ecs.component.Tmr{},
                ecs.component.Anm{ .interval = 8, .animation = .SmashJumpSmoke },
            });
        }

        if ((!state.button_a.is_down() or mov.velocity.vector[1] > 0) and sim.world.checkSignature(entity, &.{ecs.component.Jmp}, &.{})) {
            sim.world.demote(entity, &.{ecs.component.Jmp});
        }

        const wants_attack = state.button_b == .Pressed or (if (timeline.buttonStateTick(plr.id, .b, .Pressed)) |press_tick| sim.meta.ticks_elapsed - press_tick < attack_buffer else false);
        const can_attack = (if (timeline.buttonStateTick(plr.id, .b, .Pressed)) |press_tick| sim.meta.ticks_elapsed - press_tick < attack_cooldown else false) and ctr.count < attack_cooldown and sim.world.checkSignature(entity, &.{}, &.{ecs.component.Atk});

        if (wants_attack and can_attack) {
            sim.world.promote(entity, &.{ecs.component.Atk});
        }
    }
}

fn particleSystem(world: *ecs.world.World) void {
    var query = world.query(&.{
        ecs.component.Tmr,
        ecs.component.Pos,
        ecs.component.Tex,
        ecs.component.Anm,
    }, &.{
        ecs.component.Col,
        ecs.component.Plr,
    });

    while (query.next()) |entity| {
        const tmr = query.get(ecs.component.Tmr) catch unreachable;

        if (tmr.ticks == 32) {
            world.kill(entity);
        } else {
            tmr.ticks += 1;
        }
    }
}

fn attackSystem(world: *ecs.world.World, inputs: *const input.AllPlayerButtons) !void {
    var attacker_query = world.query(&.{
        ecs.component.Plr,
        ecs.component.Atk,
        ecs.component.Ctr,
        ecs.component.Pos,
    }, &.{});

    while (attacker_query.next()) |entity| {
        const plr = attacker_query.get(ecs.component.Plr) catch unreachable;
        const ctr = attacker_query.get(ecs.component.Ctr) catch unreachable;
        const pos = attacker_query.get(ecs.component.Pos) catch unreachable;

        if (ctr.count == 0) _ = try world.spawnWith(.{
            ecs.component.Atk{},
            ecs.component.Ctr{},
            ecs.component.Anm{},
            ecs.component.Dir{ .facing = switch (inputs[plr.id].dpad) {
                .North => .North,
                .South => .South,
                .West => .West,
                .East => .East,
                .NorthWest => .Northwest,
                .NorthEast => .Northeast,
                .SouthWest => .Southwest,
                .SouthEast => .Southeast,
                else => .None,
            } },
            // ecs.component.Tex{}, TODO
            ecs.component.Col{
                .dim = attack_dimensions,
                .layer = collision.Layer{ .base = false, .damaging = true },
                .mask = collision.Layer{ .base = false },
            },
            ecs.component.Pos{ .pos = pos.pos + attack_player_offset + switch (inputs[plr.id].dpad) {
                .North => @Vector(2, i32){ 0, -attack_directional_offset },
                .South => @Vector(2, i32){ 0, attack_directional_offset },
                .West => @Vector(2, i32){ -attack_directional_offset, 0 },
                .East => @Vector(2, i32){ attack_directional_offset, 0 },
                .NorthWest => @Vector(2, i32){ -attack_directional_offset, -attack_directional_offset },
                .NorthEast => @Vector(2, i32){ attack_directional_offset, -attack_directional_offset },
                .SouthWest => @Vector(2, i32){ -attack_directional_offset, attack_directional_offset },
                .SouthEast => @Vector(2, i32){ attack_directional_offset, attack_directional_offset },
                else => @Vector(2, i32){ 0, 0 },
            } },
            ecs.component.Lnk{ .child = entity },
            ecs.component.Dbg{},
        });

        ctr.count += 1;

        if (ctr.count >= attack_cooldown) {
            world.demote(entity, &.{ecs.component.Atk});
            ctr.count = 0;
        }
    }

    var attack_query = world.query(&.{
        ecs.component.Atk,
        ecs.component.Ctr,
        ecs.component.Dir,
        ecs.component.Pos,
        ecs.component.Col,
        ecs.component.Lnk,
    }, &.{
        ecs.component.Plr,
    });

    while (attack_query.next()) |entity| {
        const atk_ctr = attack_query.get(ecs.component.Ctr) catch unreachable;

        if (atk_ctr.count == attack_ticks) {
            world.kill(entity);
            continue;
        }

        atk_ctr.count += 1;

        const atk_lnk = attack_query.get(ecs.component.Lnk) catch unreachable;
        const atk_pos = attack_query.get(ecs.component.Pos) catch unreachable;
        const atk_col = attack_query.get(ecs.component.Col) catch unreachable;
        const atk_dir = attack_query.get(ecs.component.Dir) catch unreachable;

        var player_query = world.query(&.{
            ecs.component.Plr,
            ecs.component.Pos,
            ecs.component.Col,
            ecs.component.Mov,
            ecs.component.Tmr,
        }, &.{
            ecs.component.Hit,
        });

        while (player_query.next()) |plr| {
            if ((atk_lnk.child orelse continue).eq(plr)) continue;

            const plr_pos = player_query.get(ecs.component.Pos) catch unreachable;
            const plr_col = player_query.get(ecs.component.Col) catch unreachable;

            if (collision.intersects(atk_pos, atk_col, plr_pos, plr_col)) {
                const plr_mov = player_query.get(ecs.component.Mov) catch unreachable;
                const plr_tmr = player_query.get(ecs.component.Tmr) catch unreachable;

                plr_mov.velocity = switch (atk_dir.facing) {
                    .None => ecs.component.Vec2.init(0, 0),
                    .North => ecs.component.Vec2.init(0, attack_strength_medium.mul(-1)),
                    .South => ecs.component.Vec2.init(0, attack_strength_large),
                    .West => ecs.component.Vec2.init(attack_strength_large.mul(-1), attack_strength_small.mul(-1)),
                    .East => ecs.component.Vec2.init(attack_strength_large, attack_strength_small.mul(-1)),
                    .Northwest => ecs.component.Vec2.init(attack_strength_medium.mul(-1), attack_strength_medium.mul(-1)),
                    .Northeast => ecs.component.Vec2.init(attack_strength_medium, attack_strength_medium.mul(-1)),
                    .Southwest => ecs.component.Vec2.init(attack_strength_medium.mul(-1), attack_strength_medium),
                    .Southeast => ecs.component.Vec2.init(attack_strength_medium, attack_strength_medium),
                };
                plr_tmr.ticks = 0;

                world.promote(plr, &.{ecs.component.Hit});
            }
        }
    }

    var hit_query = world.query(&.{
        ecs.component.Plr,
        ecs.component.Hit,
        ecs.component.Tmr,
    }, &.{});

    while (hit_query.next()) |entity| {
        const tmr = hit_query.get(ecs.component.Tmr) catch unreachable;

        if (tmr.ticks >= hitstun) {
            world.demote(entity, &.{ecs.component.Hit});
        } else {
            tmr.ticks += 1;
        }
    }
}

fn deathSystem(sim: *simulation.Simulation) void {
    var query = sim.world.query(&.{ ecs.component.Plr, ecs.component.Pos }, &.{});

    while (query.next()) |entity| {
        const pos = query.get(ecs.component.Pos) catch unreachable;

        const x = pos.pos[0];
        const y = pos.pos[1];

        if (x < 0 or constants.world_width < x or y < 0 or constants.world_height < y) {
            sim.world.kill(entity);
            std.debug.print("entity {} died", .{entity.identifier});
        }
    }
}

fn animationSystem(world: *ecs.world.World, inputs: *const input.AllPlayerButtons) void {
    var query = world.query(&.{
        ecs.component.Plr,
        ecs.component.Mov,
        ecs.component.Tex,
        ecs.component.Anm,
    }, &.{});

    while (query.next()) |entity| {
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const mov = query.get(ecs.component.Mov) catch unreachable;
        const tex = query.get(ecs.component.Tex) catch unreachable;
        const anm = query.get(ecs.component.Anm) catch unreachable;

        const state = inputs[plr.id];

        switch (state.dpad) {
            .East, .NorthEast, .SouthEast => if (mov.velocity.vector[0] > 0) {
                tex.flip_horizontal = false;
                tex.subpos = right_texture_offset;
            },
            .West, .NorthWest, .SouthWest => if (mov.velocity.vector[0] < 0) {
                tex.flip_horizontal = true;
                tex.subpos = left_texture_offset;
            },
            else => {},
        }

        const previous = anm.animation;

        const moving = mov.velocity.vector[0] != 0 and switch (state.dpad) {
            .None, .North, .South => false,
            else => true,
        };
        const jumping = world.checkSignature(entity, &.{ecs.component.Jmp}, &.{});
        const airborne = world.checkSignature(entity, &.{ecs.component.Air}, &.{});
        const falling = !jumping and airborne and mov.velocity.vector[1] > 0;
        const crouching = mov.velocity.vector[0] == 0 and mov.velocity.vector[1] == 0 and state.dpad == .South and !airborne;
        const hit = world.checkSignature(entity, &.{ecs.component.Hit}, &.{});

        if (hit) {
            anm.animation = .SmashHit;
        } else if (moving) {
            anm.animation = .SmashRun;
        } else if (crouching) {
            anm.animation = .SmashCrouch;
        } else {
            anm.animation = .SmashIdle;
        }

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

fn forceSystem(world: *ecs.world.World, inputs: *const input.AllPlayerButtons) void {
    var query_grounded = world.query(&.{
        ecs.component.Plr,
        ecs.component.Mov,
    }, &.{
        ecs.component.Air,
        ecs.component.Hit,
    });

    while (query_grounded.next()) |_| {
        const plr = query_grounded.get(ecs.component.Plr) catch unreachable;
        const mov = query_grounded.get(ecs.component.Mov) catch unreachable;

        const target = switch (inputs[plr.id].dpad) {
            .NorthWest, .SouthWest, .West => ground_speed.mul(-1),
            .NorthEast, .SouthEast, .East => ground_speed,
            else => ecs.component.F32.init(0, 1),
        };

        const difference = target.sub(mov.velocity.x());

        const rate = if (target.abs().cmp(ecs.component.F32.init(1, 10), .gt)) ground_acceleration else ground_deceleration;

        const sign = @as(i16, @intFromBool(difference.bits > 0)) - @intFromBool(difference.bits < 0);

        const amount = difference.abs().mul(rate).mul(sign);

        mov.velocity.vector[0] += amount.bits;

        if (mov.velocity.x().abs().cmp(ground_friction, .lt)) mov.velocity.vector[0] = 0;
    }

    var query_airborne = world.query(&.{
        ecs.component.Plr,
        ecs.component.Mov,
        ecs.component.Air,
    }, &.{
        ecs.component.Hit,
    });

    while (query_airborne.next()) |_| {
        const plr = query_airborne.get(ecs.component.Plr) catch unreachable;
        const mov = query_airborne.get(ecs.component.Mov) catch unreachable;

        const target = switch (inputs[plr.id].dpad) {
            .NorthWest, .SouthWest, .West => air_speed.mul(-1),
            .NorthEast, .SouthEast, .East => air_speed,
            else => ecs.component.F32.init(0, 1),
        };

        const difference = target.sub(mov.velocity.x());

        const rate = if (target.abs().cmp(ecs.component.F32.init(1, 10), .gt)) air_acceleration else air_deceleration;

        const sign = @as(i16, @intFromBool(difference.bits > 0)) - @intFromBool(difference.bits < 0);

        const amount = difference.abs().mul(rate).mul(sign);

        mov.velocity.vector[0] += amount.bits;

        if (mov.velocity.x().abs().cmp(air_friction, .lt)) mov.velocity.vector[0] = 0;
    }
}

fn gravitySystem(world: *ecs.world.World) void {
    var query_jumping = world.query(&.{
        ecs.component.Mov,
        ecs.component.Air,
        ecs.component.Jmp,
    }, &.{
        ecs.component.Hit,
    });

    while (query_jumping.next()) |_| {
        const mov = query_jumping.get(ecs.component.Mov) catch unreachable;

        mov.velocity.vector[1] += jump_gravity.bits;
    }

    var query_falling = world.query(&.{
        ecs.component.Mov,
        ecs.component.Air,
    }, &.{
        ecs.component.Jmp,
        ecs.component.Hit,
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
        ecs.component.Tmr,
    }, &.{});

    while (query_airborne.next()) |ent1| {
        const tmr1 = query_airborne.get(ecs.component.Tmr) catch unreachable;

        tmr1.ticks += 1;

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

            if (!(col1.layer.intersects(col2.mask) or col1.mask.intersects(col2.layer))) {
                continue;
            }

            if (world.checkSignature(ent2, &.{}, &.{ecs.component.Plr}) and collision.intersectsAt(pos1, col1, pos2, col2, [_]i32{ 0, 1 })) {
                if (tmr1.ticks < 8 and world.checkSignature(ent1, &.{}, &.{ecs.component.Jmp})) {
                    world.promote(ent1, &.{ecs.component.Jmp});
                    const mov1 = query_airborne.get(ecs.component.Mov) catch unreachable;
                    mov1.velocity.vector[1] = jump_strength.bits;
                } else {
                    world.demote(ent1, &.{ecs.component.Air});
                    tmr1.ticks = 0;
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

            if (!(col1.layer.intersects(col2.mask) or col1.mask.intersects(col2.layer))) {
                continue;
            }

            if (collision.intersectsAt(pos1, col1, pos2, col2, [_]i32{ 0, 1 })) {
                airborne = false;
                break;
            }
        }

        if (airborne) world.promote(ent1, &.{ecs.component.Air});
    }
}

fn resolveCollisions(world: *ecs.world.World, collisions: *collision.CollisionQueue) void {
    for (collisions.data.keys()) |c| {
        const plrposmov1 = world.checkSignature(c.a, &.{
            ecs.component.Plr,
            ecs.component.Mov,
            ecs.component.Pos,
        }, &.{
            ecs.component.Hit,
        });
        const plrposmovhit1 = world.checkSignature(c.a, &.{
            ecs.component.Plr,
            ecs.component.Mov,
            ecs.component.Pos,
            ecs.component.Hit,
        }, &.{});
        const plrposmov2 = world.checkSignature(c.b, &.{
            ecs.component.Plr,
            ecs.component.Mov,
            ecs.component.Pos,
        }, &.{
            ecs.component.Hit,
        });
        const plrposmovhit2 = world.checkSignature(c.b, &.{
            ecs.component.Plr,
            ecs.component.Mov,
            ecs.component.Pos,
            ecs.component.Hit,
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

        if (plrposmovhit1) {
            const mov1 = world.inspect(c.a, ecs.component.Mov) catch unreachable;
            mov1.velocity = mov1.velocity.mul(ecs.component.F32.init(-1, 2));
        }

        if (plrposmovhit2) {
            const mov2 = world.inspect(c.b, ecs.component.Mov) catch unreachable;
            mov2.velocity = mov2.velocity.mul(ecs.component.F32.init(-1, 2));
        }
    }
}
