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

pub fn init(sim: *simulation.Simulation, _: *const input.InputState) !void {
    try spawnWalls(&sim.world);
    for (0..1) |id| {
        //     if (inputs[id].is_connected) {
        try spawnPlayer(&sim.world, @intCast(id));
    }
    // }
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState, invar: Invariables) !void {
    try jetpackSystem(&sim.world, inputs);

    var collisions = collision.CollisionQueue.init(invar.arena) catch @panic("could not initialize collision queue");

    movement.update(&sim.world, &collisions, invar.arena) catch @panic("movement system failed");

    try spawnSystem(&sim.world, sim.meta.ticks_elapsed);

    try deathSystem(&sim.world, &collisions);
    animator.update(&sim.world);
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

fn deathSystem(world: *ecs.world.World, _: *collision.CollisionQueue) !void {

    // Entities die when they touch the back wall (eg. both obstacles and players)
    // TODO: make this work properly
    var query = world.query(&.{ ecs.component.Pos, ecs.component.Col }, &.{});
    while (query.next()) |entity| {
        const col = try query.get(ecs.component.Col);
        const pos = try query.get(ecs.component.Pos);
        const right = pos.pos[0] + col.dim[0];
        if (right < 0) {
            world.kill(entity);
            std.debug.print("entity {} died\n", .{entity.identifier});
        }
    }
}

fn spawnSystem(world: *ecs.world.World, ticks: u64) !void {
    //The decrease causes an integer overflow. This will most likely not happen once players can die
    if (ticks % @max(20, (80 - (ticks / 160))) == 0) {
        spawnRandomObstacle(world);
    }

    if (ticks % @max(10, (60 - (ticks / 120))) == 0) {
        spawnHorizontalObstacle(world);
    }
}

fn spawnVerticalObstacleUpper(world: *ecs.world.World, length: u32) void {
    _ = world.spawnWith(.{
        ecs.component.Pos{ .pos = .{ constants.world_width, 0 } },
        ecs.component.Col{
            .dim = .{ 1 * constants.asset_resolution, constants.asset_resolution * @as(i32, @intCast(length)) },
            .layer = collision.Layer{ .base = true },
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
            .dim = .{ constants.asset_resolution, constants.asset_resolution * @as(i32, @intCast(length)) },
            .layer = collision.Layer{ .base = true },
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
            const length = std.Random.intRangeAtMost(rand, u32, 5, constants.world_height_tiles - 7);
            spawnVerticalObstacleLower(world, length);
        },
        ObstacleKind.ObstacleUpper => {
            const length = std.Random.intRangeAtMost(rand, u32, 5, constants.world_height_tiles - 7);
            spawnVerticalObstacleUpper(world, length);
        },
        ObstacleKind.ObstacleBoth => {
            const delta = std.Random.intRangeAtMost(rand, i32, 3, 8);
            spawnVerticalObstacleBoth(world, delta);
        },
    }
}

fn spawnHorizontalObstacle(world: *ecs.world.World) void {
    _ = world.spawnWith(.{
        ecs.component.Pos{
            .pos = .{
                constants.world_width,
                std.Random.intRangeLessThan(rand, i32, 0, constants.world_height),
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
            .dim = .{ 3 * constants.asset_resolution, constants.asset_resolution },
            .layer = .{ .base = true },
            .mask = .{ .base = false, .player = true },
        },
        ecs.component.Ctr{},
    }) catch unreachable;
}

fn spawnWalls(world: *ecs.world.World) !void {
    _ = try world.spawnWith(.{
        ecs.component.Pos{
            .pos = .{ 0, -32 },
        },
        ecs.component.Col{
            .dim = .{ constants.world_width, 32 },
            .layer = .{ .base = true },
            .mask = .{ .base = false, .player = true },
        },
    });
    _ = try world.spawnWith(.{
        ecs.component.Pos{
            .pos = .{ 0, constants.world_height },
        },
        ecs.component.Col{
            .dim = .{ constants.world_width, 32 },
            .layer = .{ .base = true },
            .mask = .{ .base = false, .player = true },
        },
    });
}

fn spawnPlayer(world: *ecs.world.World, id: u32) !void {
    _ = try world.spawnWith(.{
        ecs.component.Plr{ .id = @intCast(id) },
        ecs.component.Pos{ .pos = .{ 8, @divTrunc(constants.world_height, 2) } },
        ecs.component.Mov{
            .acceleration = player_gravity,
        },
        ecs.component.Col{
            .dim = .{ constants.asset_resolution, constants.asset_resolution },
            .layer = collision.Layer{ .base = false, .player = true },
            .mask = collision.Layer{ .base = false, .player = false },
        },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/kattis.png"),
            .tint = constants.player_colors[id],
        },
        ecs.component.Anm{ .animation = Animation.KattisFly, .interval = 8, .looping = true },
    });
}
