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

const PlayerChange = enum { remove, add, nothing };

const colors: [8]rl.Color = .{
    rl.Color.red,
    rl.Color.green,
    rl.Color.blue,
    rl.Color.yellow,
    rl.Color.magenta,
    rl.Color.sky_blue,
    rl.Color.brown,
    rl.Color.white,
};

const ready_strings: [2][:0]const u8 = .{
    "Not Ready",
    "Ready",
};

pub fn init(_: *simulation.Simulation, _: *const input.InputState) !void {}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState, rt: Invariables) !void {
    var players = sim.world.query(&.{ecs.component.Plr}, &.{});
    var player_changes = [_]PlayerChange{.nothing} ** inputs.len;
    var player_ids: [inputs.len]?ecs.entity.Entity = [_]?ecs.entity.Entity{null} ** inputs.len;
    var player_count: u8 = 0;

    while (players.next()) |entity| {
        const plr = players.get(ecs.component.Plr) catch unreachable;
        player_ids[plr.id] = entity;
        player_count += 1;
    }

    for (inputs, 0..) |ins, index| {
        if (ins.is_connected and player_ids[index] == null) {
            player_changes[index] = .add;
            player_count += 1;
        }

        if (!ins.is_connected and player_ids[index] != null) {
            player_changes[index] = .remove;
        }
    }

    for (player_changes, player_ids, 0..) |change, entity, index| {
        if (change == .add) {
            player_ids[index] = try sim.world.spawnWith(.{
                ecs.component.Plr{ .id = @truncate(index) },
                ecs.component.Pos{ .pos = .{ 256, 144 } },
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/kattis.png"),
                    .tint = colors[index],
                },
                ecs.component.Mov{},
                ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
                ecs.component.Ctr{ .id = @truncate(index), .counter = 0 },
                ecs.component.Txt{ .string = ready_strings[0], .color = 0x666666FF, .subpos = .{ 0, -10 }, .font_size = 12 },
            });
        } else if (change == .remove) {
            if (entity) |e| {
                sim.world.kill(e);
            }
        }
    }

    var collisions = collision.CollisionQueue.init(rt.arena) catch @panic("collision");

    try inputSystem(&sim.world, inputs);
    movement.update(&sim.world, &collisions, rt.arena) catch @panic("movement");
    animator.update(&sim.world); // I don't think this should be here

    // Count ready players
    var ready_count: u8 = 0;
    for (player_ids) |player| {
        if (player) |p| {
            const ctr = try sim.world.inspect(p, ecs.component.Ctr);
            if (ctr.counter == 1) ready_count += 1;
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

fn inputSystem(world: *ecs.world.World, inputs: *const input.InputState) !void {
    var query = world.query(&.{ ecs.component.Mov, ecs.component.Plr, ecs.component.Anm, ecs.component.Ctr, ecs.component.Txt }, &.{});
    while (query.next()) |_| {
        const mov = try query.get(ecs.component.Mov);
        const plr = try query.get(ecs.component.Plr);
        const ctr = try query.get(ecs.component.Ctr);
        const txt = try query.get(ecs.component.Txt);
        const state = inputs[plr.id];
        mov.velocity.set([_]i16{
            @intCast(3 * state.horizontal()),
            @intCast(3 * state.vertical()),
        });

        const anm = try query.get(ecs.component.Anm);
        if (state.horizontal() + state.vertical() != 0) {
            anm.animation = Animation.KattisRun;
            anm.interval = 8;
        } else {
            anm.animation = Animation.KattisIdle;
            anm.interval = 16;
        }

        if (state.button_b.pressed()) {
            txt.string = ready_strings[1];
            ctr.counter = 1;
        }
        if (state.button_a.pressed()) {
            txt.string = ready_strings[0];
            ctr.counter = 0;
        }
    }
}
