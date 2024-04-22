// TODO: Make a lobby minigame.

const AssetManager = @import("../AssetManager.zig");
const Animation = @import("../animation/animations.zig").Animation;
const rl = @import("raylib");
const simulation = @import("../simulation.zig");
const input = @import("../input.zig");
const ecs = @import("../ecs/ecs.zig");
const std = @import("std");
const movement = @import("../physics/movement.zig");
const collision = @import("../physics/collision.zig");
const animator = @import("../animation/animator.zig");

const PlayerChange = enum { remove, add, nothing };

pub fn init(_: *simulation.Simulation, _: *const input.InputState) !void {}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState, arena: std.mem.Allocator) !void {
    var players = sim.world.query(&.{ecs.component.Plr}, &.{});
    var player_changes = [_]PlayerChange{.nothing} ** inputs.len;
    var player_ids: [inputs.len]?ecs.entity.Entity = [_]?ecs.entity.Entity{null} ** inputs.len;

    while (players.next()) |entity| {
        const plr = players.get(ecs.component.Plr) catch unreachable;
        player_ids[plr.id] = entity;
    }

    for (inputs, 0..) |ins, index| {
        if (ins.is_connected and player_ids[index] == null) {
            player_changes[index] = .add;
        }

        if (!ins.is_connected and player_ids[index] != null) {
            player_changes[index] = .remove;
        }
    }

    for (player_changes, player_ids, 0..) |change, entity, index| {
        if (change == .add) {
            _ = try sim.world.spawnWith(.{
                ecs.component.Plr{ .id = @truncate(index) },
                ecs.component.Pos{ .pos = .{ 256, 36 } },
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/kattis.png"),
                    .tint = rl.Color.white,
                },
                ecs.component.Mov{},
                ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
            });
        } else if (change == .remove) {
            if (entity) |e| {
                sim.world.kill(e);
            }
        }
    }

    var collisions = collision.CollisionQueue.init(arena) catch @panic("collision");

    try inputSystem(&sim.world, inputs);
    movement.update(&sim.world, &collisions, arena) catch @panic("movement");
    animator.update(&sim.world); // I don't think this should be here
}

fn inputSystem(world: *ecs.world.World, inputs: *const input.InputState) !void {
    var query = world.query(&.{ ecs.component.Mov, ecs.component.Plr, ecs.component.Anm }, &.{});
    while (query.next()) |_| {
        const mov = try query.get(ecs.component.Mov);
        const plr = try query.get(ecs.component.Plr);
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
    }
}
