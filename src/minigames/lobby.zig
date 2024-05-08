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

const ready_strings: [2][:0]const u8 = .{
    "Not Ready",
    "Ready",
};

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
    var players = sim.world.query(&.{ecs.component.Plr}, &.{});
    var player_changes = [_]PlayerChange{.nothing} ** constants.max_player_count;
    var player_ids: [constants.max_player_count]?ecs.entity.Entity = [_]?ecs.entity.Entity{null} ** constants.max_player_count;
    var player_count: u8 = 0;

    while (players.next()) |entity| {
        const plr = players.get(ecs.component.Plr) catch unreachable;
        player_ids[plr.id] = entity;
        player_count += 1;
    }

    const inputs = timeline.latest();

    for (inputs, 0..) |ins, index| {
        if (ins.is_connected() and player_ids[index] == null) {
            player_changes[index] = .add;
            player_count += 1;
        }

        if (!ins.is_connected() and player_ids[index] != null) {
            player_changes[index] = .remove;
        }
    }

    for (player_changes, player_ids, 0..) |change, entity, index| {
        if (change == .add) {
            player_ids[index] = try sim.world.spawnWith(.{
                ecs.component.Plr{ .id = @truncate(index) },
                ecs.component.Pos{ .pos = .{ 256, 144 } },
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/smash_cat.png"),
                    .w = 2,
                    .h = 1,
                    .tint = constants.player_colors[index],
                    .subpos = right_texture_offset,
                },
                ecs.component.Mov{},
                ecs.component.Anm{ .animation = Animation.SmashIdle, .interval = 16, .looping = true },
                ecs.component.Ctr{ .id = @truncate(index), .count = 0 },
                ecs.component.Txt{ .string = ready_strings[0], .color = 0x999999FF, .subpos = .{ 0, -10 }, .font_size = 12 },
                ecs.component.Col{ .dim = .{ 16, 8 }, .layer = .{ .base = false } },
                // ecs.component.Dbg{},
            });
        } else if (change == .remove) {
            if (entity) |e| {
                sim.world.kill(e);
            }
        }
    }

    var collisions = collision.CollisionQueue.init(rt.arena) catch @panic("collision");

    try inputSystem(&sim.world, inputs);
    try flipSystem(&sim.world, inputs);
    movement.update(&sim.world, &collisions, rt.arena) catch @panic("movement");
    try containSystem(&sim.world);
    animator.update(&sim.world);

    // Count ready players
    var ready_count: u8 = 0;
    for (player_ids) |player| {
        if (player) |p| {
            const ctr = try sim.world.inspect(p, ecs.component.Ctr);
            if (ctr.count == 1) ready_count += 1;
        }
    }

    if (ready_count == player_count) {
        // Find the game-wheel minigame and switch to it.
        // If not found, returns to game 0.
        sim.meta.minigame_id = 0;
        for (rt.minigames_list, 0..) |minigame, minigame_id| {
            if (std.mem.eql(u8, minigame.name, "gamewheel")) {
                sim.meta.minigame_id = minigame_id;
                break;
            }
        }
    }
}

fn inputSystem(world: *ecs.world.World, inputs: input.AllPlayerButtons) !void {
    var query = world.query(&.{ ecs.component.Mov, ecs.component.Plr, ecs.component.Anm, ecs.component.Ctr, ecs.component.Txt }, &.{});
    while (query.next()) |_| {
        const mov = try query.get(ecs.component.Mov);
        const plr = try query.get(ecs.component.Plr);
        const ctr = try query.get(ecs.component.Ctr);
        const txt = try query.get(ecs.component.Txt);
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

        if (state.button_b == .Pressed) {
            txt.string = ready_strings[1];
            ctr.count = 1;
        }
        if (state.button_a == .Pressed) {
            txt.string = ready_strings[0];
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
        const plr = try query.get(ecs.component.Plr);
        _ = plr;
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
