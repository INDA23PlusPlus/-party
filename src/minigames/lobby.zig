const std = @import("std");
const rl = @import("raylib");
const AssetManager = @import("../AssetManager.zig");
const Animation = @import("../animation/animations.zig").Animation;
const Invariables = @import("../Invariables.zig");
const simulation = @import("../simulation.zig");
const input = @import("../input.zig");
const ecs = @import("../ecs/ecs.zig");
const movement = @import("../physics/movement.zig");
const collision = @import("../physics/collision.zig");
const animator = @import("../animation/animator.zig");
const constants = @import("../constants.zig");

const PlayerChange = enum { remove, add, nothing };

const left_texture_offset = [_]i32{ 0, -8 };
const right_texture_offset = [_]i32{ -16, -8 };

pub fn init(sim: *simulation.Simulation, _: input.Timeline) !void {
    // Background
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{},
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/tron_map.png"),
            .w = 32,
            .h = 18,
        },
    });
}

pub fn update(sim: *simulation.Simulation, timeline: input.Timeline, rt: Invariables) !void {
    const inputs = timeline.latest();
    var current_players = sim.world.query(&.{ecs.component.Plr}, &.{});
    var player_changes = [_]PlayerChange{.nothing} ** constants.max_player_count;
    var player_ids: [constants.max_player_count]?ecs.entity.Entity = [_]?ecs.entity.Entity{null} ** constants.max_player_count;
    var player_count: u8 = 0;
    var collisions = collision.CollisionQueue.init(rt.arena) catch @panic("collision");

    while (current_players.next()) |entity| {
        const plr = current_players.get(ecs.component.Plr) catch unreachable;
        player_ids[plr.id] = entity;
        player_count += 1;
    }

    for (inputs, 0..) |ins, index| {
        if (ins.is_connected() and player_ids[index] == null) {
            player_changes[index] = .add;
            player_count += 1;
        }

        if (!ins.is_connected() and player_ids[index] != null) {
            player_changes[index] = .remove;
            player_count -= 1;
        }
    }

    for (player_changes, player_ids, 0..) |change, entity, index| {
        if (change == .add) {
            var random = sim.meta.minigame_prng.random();
            const x = (constants.world_width / 2) + @as(i32, random.int(i8));
            const y = (constants.world_height / 2) + @as(i32, random.int(i8));

            const text = try sim.world.spawnWith(.{
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/lobby.png"),
                    .v = 1,
                    .w = 4,
                    .subpos = .{ -18, 0 },
                    .tint = rl.Color.red,
                },
                ecs.component.Pos{},
            });
            player_ids[index] = try sim.world.spawnWith(.{
                ecs.component.Plr{ .id = @truncate(index) },
                ecs.component.Pos{ .pos = .{ x, y } },
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/smash_cat.png"),
                    .w = 2,
                    .h = 1,
                    .tint = constants.player_colors[index],
                    .subpos = right_texture_offset,
                },
                ecs.component.Mov{},
                ecs.component.Anm{ .animation = Animation.SmashIdle, .interval = 16, .looping = true },
                ecs.component.Ctr{ .count = 0 },
                ecs.component.Col{ .dim = .{ 16, 8 }, .layer = .{ .base = false } },
                ecs.component.Lnk{ .child = text },
            });
        } else if (change == .remove) {
            if (entity) |e| {
                sim.world.kill(e);
            }
        }
    }

    try inputSystem(&sim.world, inputs);
    try flipSystem(&sim.world, inputs);
    movement.update(&sim.world, &collisions, rt.arena) catch @panic("movement");
    try textFollowSystem(&sim.world);
    try containSystem(&sim.world);
    animator.update(&sim.world);

    // Count ready players
    var ready_count: u8 = 0;
    var player_querry = sim.world.query(&.{ ecs.component.Plr, ecs.component.Ctr }, &.{});
    while (player_querry.next()) |player| {
        const ctr = try sim.world.inspect(player, ecs.component.Ctr);
        if (ctr.count == 1) ready_count += 1;
    }

    if (ready_count == player_count and player_count > 0) {
        sim.meta.minigame_id = constants.minigame_gamewheel;
    }
}

fn inputSystem(world: *ecs.world.World, inputs: input.AllPlayerButtons) !void {
    var query = world.query(&.{
        ecs.component.Mov,
        ecs.component.Plr,
        ecs.component.Anm,
        ecs.component.Ctr,
        ecs.component.Lnk,
    }, &.{});

    while (query.next()) |_| {
        const mov = query.get(ecs.component.Mov) catch unreachable;
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        const lnk = query.get(ecs.component.Lnk) catch unreachable;
        const state = inputs[plr.id];

        mov.velocity.set([_]i16{
            @intCast(state.horizontal() * 3),
            @intCast(state.vertical() * -3),
        });

        const anm = try query.get(ecs.component.Anm);

        if (state.dpad != input.InputDirection.None) {
            anm.animation = Animation.SmashRun;
            anm.interval = 8;
        } else {
            anm.animation = Animation.SmashIdle;
            anm.interval = 16;
        }

        const text = lnk.child orelse continue;
        const text_tex = try world.inspect(text, ecs.component.Tex);

        if (state.button_a == .Pressed) {
            text_tex.v = 0;
            text_tex.subpos = .{ -6, 0 };
            text_tex.tint = rl.Color.green;
            ctr.count = 1;
        }
        if (state.button_b == .Pressed) {
            text_tex.v = 1;
            text_tex.subpos = .{ -18, 0 };
            text_tex.tint = rl.Color.red;
            ctr.count = 0;
        }
    }
}

fn flipSystem(world: *ecs.world.World, inputs: input.AllPlayerButtons) !void {
    var query = world.query(&.{ ecs.component.Plr, ecs.component.Tex, ecs.component.Mov }, &.{});

    while (query.next()) |_| {
        const plr = try query.get(ecs.component.Plr);
        const tex = try query.get(ecs.component.Tex);
        const mov = try query.get(ecs.component.Mov);
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
    }
}

fn containSystem(world: *ecs.world.World) !void {
    var query = world.query(&.{ ecs.component.Plr, ecs.component.Pos, ecs.component.Col }, &.{});

    while (query.next()) |_| {
        const pos = try query.get(ecs.component.Pos);
        const col = try query.get(ecs.component.Col);

        if (pos.pos[0] < 16) {
            pos.pos[0] = 16;
        }
        if (pos.pos[0] + col.dim[0] > constants.world_width - 16) {
            pos.pos[0] = constants.world_width - col.dim[0] - 16;
        }
        if (pos.pos[1] < 16) {
            pos.pos[1] = 16;
        }
        if (pos.pos[1] + col.dim[1] > constants.world_height - 16) {
            pos.pos[1] = constants.world_height - col.dim[1] - 16;
        }
    }
}

fn textFollowSystem(world: *ecs.world.World) !void {
    var query = world.query(&.{
        ecs.component.Plr,
        ecs.component.Pos,
        ecs.component.Lnk,
    }, &.{});

    while (query.next()) |_| {
        const pos = query.get(ecs.component.Pos) catch unreachable;
        const lnk = query.get(ecs.component.Lnk) catch unreachable;
        const text = lnk.child orelse continue;
        const text_pos = try world.inspect(text, ecs.component.Pos);

        text_pos.pos = pos.pos + [_]i32{ 0, -16 };
    }
}
