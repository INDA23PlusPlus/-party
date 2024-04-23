const std = @import("std");
const root = @import("root");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const render = @import("../render.zig");
const AssetManager = @import("../AssetManager.zig");
const Invariables = @import("../Invariables.zig");
const input = @import("../input.zig");
const Animation = @import("../animation/animations.zig").Animation;
const animator = @import("../animation/animator.zig");
const constants = @import("../constants.zig");
const movement = @import("../physics/movement.zig");
const collision = @import("../physics/collision.zig");
const Vec2 = ecs.component.Vec2;
const F32 = ecs.component.F32;

var prng = std.rand.DefaultPrng.init(555);
const rand = prng.random();

const obstacle_height_base = 7;
const obstacle_height_delta = 6;

const player_gravity = Vec2.init(0, F32.init(1, 10));
const player_boost = Vec2.init(0, F32.init(-1, 4));
const obstacle_velocity = Vec2.init(-8, 0);
const obstacle_lifetime: usize = 200; // ticks until despawning obstacles, increase if they die too early
const obstacle_spawn_delay_initial: usize = 120;
const obstacle_spawn_delay_min: usize = 10;
const obstacle_spawn_delay_delta: usize = 5;

const ObstacleKind = enum { ObstacleUpper, ObstacleLower, ObstacleBoth };

fn spawnVerticalObstacleUpper(world: *ecs.world.World, length: u32) void {
    _ = world.spawnWith(.{
        ecs.component.Pos{ .pos = .{ constants.world_width, 0 } },
        ecs.component.Col{
            .dim = .{ 1 * constants.asset_resolution, constants.asset_resolution * @as(i32, @intCast(length)) },
            .layer = collision.Layer{ .base = false, .player = false },
            .mask = collision.Layer{ .base = false, .player = true },
        },
        ecs.component.Mov{ .velocity = obstacle_velocity },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/error.png"),
            .w = 1,
            .h = length,
        },
        ecs.component.Ctr{},
    }) catch unreachable;
}

fn spawnVerticalObstacleLower(world: *ecs.world.World, length: u32) void {
    _ = world.spawnWith(.{
        ecs.component.Pos{ .pos = .{ constants.world_width, constants.world_height - @as(i32, @intCast(length)) * constants.asset_resolution } },
        ecs.component.Col{
            .dim = .{ 1 * constants.asset_resolution, constants.asset_resolution * @as(i32, @intCast(length)) },
            .layer = collision.Layer{ .base = false, .player = false },
            .mask = collision.Layer{ .base = false, .player = true },
        },
        ecs.component.Mov{ .velocity = obstacle_velocity },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/error.png"),
            .w = 1,
            .h = length,
        },
        ecs.component.Ctr{},
    }) catch unreachable;
}

fn spawnVerticalObstacleBoth(world: *ecs.world.World, delta: i32) void {
    spawnVerticalObstacleUpper(world, @intCast(@divTrunc(constants.world_height_tiles - delta, 2)));
    spawnVerticalObstacleLower(world, @intCast(@divTrunc(constants.world_height_tiles - delta, 2)));
}

pub fn spawnRandomObstacle(world: *ecs.world.World) void {
    const kind = std.Random.enumValue(rand, ObstacleKind);
    switch (kind) {
        ObstacleKind.ObstacleLower => {
            const length = std.Random.intRangeAtMost(rand, u32, 1, constants.world_height_tiles - 1);
            spawnVerticalObstacleLower(world, length);
        },
        ObstacleKind.ObstacleUpper => {
            const length = std.Random.intRangeAtMost(rand, u32, 1, constants.world_height_tiles - 1);
            spawnVerticalObstacleUpper(world, length);
        },
        ObstacleKind.ObstacleBoth => {
            const delta = std.Random.intRangeAtMost(rand, i32, 1, 8);
            spawnVerticalObstacleBoth(world, delta);
        },
    }
}

fn spawnHorizontalObstacle(world: *ecs.world.World) void {
    _ = world.spawnWith(.{
        ecs.component.Pos{
            .pos = .{
                constants.world_width,
                rl.getRandomValue(0, constants.world_height), // is this ok?
            },
        },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/error.png"),
            .u = 0,
            .v = 0,
            .w = 3,
            .h = 1,
        },
        ecs.component.Mov{
            .velocity = obstacle_velocity,
        },
        ecs.component.Col{
            .dim = .{ 48, 16 },
            .layer = .{ .base = true, .killing = true },
            .mask = .{ .base = true, .player = true },
        },
        ecs.component.Ctr{},
    }) catch unreachable;
}

pub fn init(sim: *simulation.Simulation, _: *const input.InputState) !void {
    for (0..constants.max_player_count) |id| {
        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = @intCast(id) },
            ecs.component.Pos{ .pos = .{ 8, 0 } },
            ecs.component.Mov{
                .acceleration = player_gravity,
            },
            //Somas lösning
            ecs.component.Col{
                .dim = .{ 16, 16 },
                .layer = collision.Layer{ .base = false, .player = true },
                .mask = collision.Layer{ .base = false, .player = false },
            },
            //Elliots lösning
            // ecs.component.Col{
            //     .dim = .{ 16, 16 },
            //     .layer = .{ .base = true, .player = true },
            //     .mask = .{
            //         .base = false,
            //         .killing = true,
            //     },
            // },
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/kattis.png"),
                .tint = constants.player_colors[id],
            },
            ecs.component.Anm{ .animation = Animation.KattisFly, .interval = 8, .looping = true },
        });
    }
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState, invar: Invariables) !void {
    std.debug.print("\nBEfor jet\n", .{});

    try jetpackSystem(&sim.world, inputs);
    std.debug.print("\nAFter jet\n", .{});

    var collisions = collision.CollisionQueue.init(invar.arena) catch @panic("could not initialize collision queue");
    std.debug.print("\nAFter Collsion\n", .{});

    movement.update(&sim.world, &collisions, invar.arena) catch @panic("movement system failed");
    std.debug.print("\nAFter move\n", .{});

    //Somas lösning

    // sim.meta.ticks_elapsed += 1;
    // try deathSystemS(&sim.world);
    // animator.update(&sim.world);
    //*const fn (*simulation.Simulation, *const [8]input.PlayerInputState, Invariables) error{SpawnLimitExceeded,NullQuery,DeadInspection,InvalidInspection}!void', found
    //*const fn (*simulation.Simulation, *const [8]input.PlayerInputState, mem.Allocator) @typeInfo(@typeInfo(@TypeOf(minigames.hot_n_steamy.update)).Fn.return_type.?).ErrorUnion.error_set!void
    // fn gravitySystem(world: *ecs.world.World) !void {
    //     var query = world.query(&.{ecs.component.Mov}, &.{});
    //     while (query.next()) |_| {
    //         const mov = try query.get(ecs.component.Mov);
    //         mov.acceleration = mov.acceleration.add(gravity);
    //     }
    // }
    //Elliots lösning
    try spawnSystem(&sim.world, sim.meta.ticks_elapsed);
    std.debug.print("\nAFter spawn\n", .{});

    try deathSystem(&sim.world, &collisions);
    std.debug.print("\nAFter deatg\n", .{});
    // try despawnSystem(&sim.world, );
    animator.update(&sim.world);
    std.debug.print("\nAFter anime\n", .{});
}

fn jetpackSystem(world: *ecs.world.World, inputs: *const input.InputState) !void {
    var query = world.query(&.{ ecs.component.Mov, ecs.component.Plr }, &.{});
    while (query.next()) |_| {
        const plr = try query.get(ecs.component.Plr);
        const mov = try query.get(ecs.component.Mov);
        const state = inputs[plr.id];
        if (state.is_connected) {
            if (state.button_up.is_down) {
                mov.velocity = mov.velocity.add(player_boost);
            }
        }
    }
}

fn deathSystem(world: *ecs.world.World, collisions: *collision.CollisionQueue) !void {
    for (collisions.collisions.keys()) |col| {
        // TODO: right now it is random whether the player or obstacle dies, so we have to kill both
        // i call it a feature :,)
        // maybe world.checkSignature (?) to see if it is a player?
        std.debug.print("\nMAHAHAHA\n\n", .{});
        world.kill(col.a);
        world.kill(col.b);
        std.debug.print("entity {} died\n", .{col.b.identifier});
    }
}

fn despawnSystem(world: *ecs.world.World) !void {
    var query = world.query(&.{ecs.component.Ctr}, &.{});
    while (query.next()) |entitity| {
        var counter = try query.get(ecs.component.Ctr);
        if (counter == obstacle_lifetime) {
            world.kill(entitity);
        } else counter += 1;
    }
}

fn spawnSystem(world: *ecs.world.World, ticks: usize) !void {
    if (ticks % @max(20, (80 - (ticks / 160))) == 0) {
        spawnRandomObstacle(world);
    }

    if (ticks % @max(10, (60 - (ticks / 120))) == 0) {
        spawnHorizontalObstacle(world);
    }
}
