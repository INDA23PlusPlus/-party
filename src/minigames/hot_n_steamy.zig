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
var player_finish_order: [8]u32 = [8]u32{ undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined };
var current_placement: u32 = 0;
var ticks_at_start = undefined;
const obstacle_height_base = 7;
const obstacle_height_delta = 6;

const player_gravity = Vec2.init(0, F32.init(1, 10));
const player_boost = Vec2.init(0, F32.init(-1, 4));
const vertical_obstacle_velocity = Vec2.init(-4, 0);
const horizontal_obstacle_velocity = Vec2.init(-6, 0);

const ObstacleKind = enum { ObstacleUpper, ObstacleLower, ObstacleBoth };

const background_layers = [_][]const u8{
    "assets/sky_background_0.png",
    "assets/sky_background_1.png",
    "assets/sky_background_2.png",
};

const background_scroll = [_]i16{ -1, -2, -3 };

const scrollable_uid = 0;
const killable_uid = 1;

// FIX: Find some other way to differentiate entities without the ugly Uid
// TODO: Change obstacles and players to use the Bnd component for bounds checking

fn spawnBackground(world: *ecs.world.World) !void {
    const n = @min(background_layers.len, background_scroll.len);
    for (0..n) |i| {
        for (0..2) |ix| {
            _ = try world.spawnWith(.{
                ecs.component.Uid{ .uid = scrollable_uid },
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash(background_layers[i]),
                    .w = constants.world_width_tiles,
                    .h = constants.world_height_tiles,
                },
                ecs.component.Pos{ .pos = .{ @intCast(constants.world_width * ix), 0 } },
                ecs.component.Mov{
                    .velocity = Vec2.init(background_scroll[i], 0),
                },
                ecs.component.Bnd{
                    .bounds = .{
                        .left = 0,
                        .right = constants.world_width,
                        .top = 0,
                        .bottom = constants.world_height,
                    },
                },
                ecs.component.Col{
                    .dim = .{ constants.world_width, constants.world_height },
                    .layer = .{ .base = false },
                    .mask = .{ .base = false },
                },
            });
        }
    }
}

pub fn init(sim: *simulation.Simulation, _: []const input.InputState) !void {
    _ = try spawnBackground(&sim.world);
    for (0..constants.max_player_count) |id| {
    ticks_at_start = sim.meta.ticks_elapsed;
    current_placement = 0;
    player_finish_order = [8]u32{ undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined };
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{},
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/hns_background.png"),
            .w = 32,
            .h = 18,
        },
    });
    //TODO Change so it spawns one player for all current active players
    for (0..3) |id| {
        //Condtion for only spawning player that are connected DOESN'T WORK AT THE MOMENT
        // if (inputs[id].is_connected) {
        try spawnPlayer(&sim.world, @intCast(id));
        // }
    }
}

pub fn update(sim: *simulation.Simulation, inputs: []const input.InputState, invar: Invariables) !void {
    try jetpackSystem(&sim.world, &inputs[inputs.len - 1]);

    var collisions = collision.CollisionQueue.init(invar.arena) catch @panic("could not initialize collision queue");

    movement.update(&sim.world, &collisions, invar.arena) catch @panic("movement system failed");

    try collisionSystem(&sim.world);

    try pushSystem(&sim.world, &collisions);

    try spawnSystem(&sim.world, sim.meta.ticks_elapsed - ticks_at_start);

    try deathSystem(&sim.world, &collisions);

    try scrollSystem(&sim.world);

    animator.update(&sim.world);
    //TODO Change number so it uses current active players instead
    if (current_placement == 3) {
        sim.meta.score[player_finish_order[2]] += 10;
        sim.meta.score[player_finish_order[1]] += 5;
        sim.meta.score[player_finish_order[0]] += 2;
        std.debug.print("{}\n", .{player_finish_order[2]});
        std.debug.print("{}\n", .{sim.meta.score[player_finish_order[2]]});
        std.debug.print("Moving to scoreboard\n", .{});
        //TODO Change so it rdirect to the scoreboard once scoreboard mingame is implemented
        sim.meta.minigame_id = 0;
    }
}

fn scrollSystem(world: *ecs.world.World) !void {
    var query = world.query(&.{ ecs.component.Pos, ecs.component.Bnd, ecs.component.Col, ecs.component.Uid }, &.{});
    while (query.next()) |_| {
        const uid = try query.get(ecs.component.Uid);
        if (uid.uid != scrollable_uid) continue;
        const pos = try query.get(ecs.component.Pos);
        const bnd = try query.get(ecs.component.Bnd);
        const col = try query.get(ecs.component.Col);
        if (pos.pos[0] + col.dim[0] + col.off[0] <= bnd.bounds.left + 4) { // +4 to hide visible seams
            pos.pos[0] = bnd.bounds.right - col.off[0];
        }
    }
}

fn collisionSystem(world: *ecs.world.World) !void {
    var query = world.query(&.{ ecs.component.Plr, ecs.component.Col, ecs.component.Pos, ecs.component.Mov }, &.{});
    while (query.next()) |_| {
        const pos = try query.get(ecs.component.Pos);
        const mov = try query.get(ecs.component.Mov);
        const col = try query.get(ecs.component.Col);
        const y = pos.pos[1];
        if (y < 0) {
            mov.velocity.vector[1] = 0;
            pos.pos[1] = 0;
        } else if ((y + col.dim[1]) > constants.world_height) {
            mov.velocity.vector[1] = 0;
            pos.pos[1] = constants.world_height - col.dim[1];
        }
    }
}

fn pushSystem(world: *ecs.world.World, _: *collision.CollisionQueue) !void {
    var query = world.query(&.{ ecs.component.Plr, ecs.component.Col, ecs.component.Pos, ecs.component.Mov }, &.{});
    while (query.next()) |_| {
        var pos = try query.get(ecs.component.Pos);
        const col = try query.get(ecs.component.Col);
        var obst_query = world.query(&.{ ecs.component.Col, ecs.component.Pos, ecs.component.Mov, ecs.component.Uid }, &.{ecs.component.Plr});
        while (obst_query.next()) |_| {
            const uid = try obst_query.get(ecs.component.Uid);
            if (uid.uid == scrollable_uid) continue;
            const obst_pos = try obst_query.get(ecs.component.Pos);
            const obst_col = try obst_query.get(ecs.component.Col);
            const obst_mov = try obst_query.get(ecs.component.Mov);
            if (collision.intersectsAt(pos, col, obst_pos, obst_col, [_]i32{ 1, 0 })) {
                pos.pos[0] += obst_mov.velocity.x().toInt();
            }
        }
    }
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
    var query = world.query(&.{ ecs.component.Pos, ecs.component.Col, ecs.component.Uid }, &.{});
    while (query.next()) |entity| {
        const uid = try query.get(ecs.component.Uid);
        if (uid.uid != killable_uid) continue;

        const col = try query.get(ecs.component.Col);
        const pos = try query.get(ecs.component.Pos);

        const right = pos.pos[0] + col.dim[0] + col.off[0];
        if (right < 0) {
            if (world.checkSignature(entity, &.{ecs.component.Plr}, &.{})) {
                const plr = try world.inspect(entity, ecs.component.Plr);
                player_finish_order[current_placement] = plr.id;
                current_placement += 1;
            }
            world.kill(entity);
            std.debug.print("entity {} died\n", .{entity.identifier});
        }
    }
}

fn spawnSystem(world: *ecs.world.World, ticks: u64) !void {
    if (ticks % @max(20, (80 -| (ticks / 160))) == 0) {
        spawnRandomObstacle(world);
    }

    if (ticks % @max(10, (60 -| (ticks / 120))) == 0) {
        spawnHorizontalObstacle(world);
    }
}

fn spawnVerticalObstacleUpper(world: *ecs.world.World, length: u32) void {
    _ = world.spawnWith(.{
        ecs.component.Uid{ .uid = killable_uid },
        ecs.component.Pos{ .pos = .{ constants.world_width, 0 } },
        ecs.component.Col{
            .dim = .{ 1 * constants.asset_resolution, constants.asset_resolution * @as(i32, @intCast(length)) },
            .layer = collision.Layer{ .base = true, .pushing = true },
            .mask = collision.Layer{ .base = false, .player = true },
        },
        ecs.component.Mov{ .velocity = vertical_obstacle_velocity },
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
        ecs.component.Uid{ .uid = killable_uid },
        ecs.component.Pos{ .pos = .{ constants.world_width, constants.world_height - @as(i32, @intCast(length)) * constants.asset_resolution } },
        ecs.component.Col{
            .dim = .{ constants.asset_resolution, constants.asset_resolution * @as(i32, @intCast(length)) },
            .layer = collision.Layer{ .base = true },
            .mask = collision.Layer{ .base = false, .player = true },
        },
        ecs.component.Mov{ .velocity = vertical_obstacle_velocity },
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
            const length = std.Random.intRangeAtMost(rand, u32, 7, constants.world_height_tiles - 5);
            spawnVerticalObstacleLower(world, length);
        },
        ObstacleKind.ObstacleUpper => {
            const length = std.Random.intRangeAtMost(rand, u32, 7, constants.world_height_tiles - 5);
            spawnVerticalObstacleUpper(world, length);
        },
        ObstacleKind.ObstacleBoth => {
            const delta = std.Random.intRangeAtMost(rand, i32, 4, 8);
            spawnVerticalObstacleBoth(world, delta);
        },
    }
}

fn spawnHorizontalObstacle(world: *ecs.world.World) void {
    _ = world.spawnWith(.{
        ecs.component.Uid{ .uid = killable_uid },
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
            .velocity = horizontal_obstacle_velocity,
        },
        ecs.component.Col{
            .dim = .{ 3 * constants.asset_resolution, constants.asset_resolution },
            .layer = .{ .base = true, .pushing = true },
            .mask = .{ .base = false, .player = true },
        },
        ecs.component.Ctr{},
    }) catch unreachable;
}

fn spawnPlayer(world: *ecs.world.World, id: u32) !void {
    _ = try world.spawnWith(.{
        ecs.component.Uid{ .uid = killable_uid },
        ecs.component.Plr{ .id = @intCast(id) },
        ecs.component.Pos{ .pos = .{ std.Random.intRangeAtMost(rand, i32, 64, 112), @divTrunc(constants.world_height, 2) } },
        // ecs.component.Pos{ .pos = .{ constants.world_width - 16, 0 } },
        ecs.component.Mov{
            .acceleration = player_gravity,
        },
        ecs.component.Col{
            .dim = .{ 16, 12 },
            .layer = collision.Layer{ .base = false, .player = true },
            .mask = collision.Layer{ .base = false, .player = false, .pushing = true },
        },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/kattis.png"),
            .tint = constants.player_colors[id],
            .subpos = .{ 0, -2 },
        },
        ecs.component.Anm{ .animation = Animation.KattisFly, .interval = 8, .looping = true },
    });
}
