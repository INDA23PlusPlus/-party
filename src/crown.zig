const std = @import("std");
const ecs = @import("ecs/ecs.zig");
const Simulation = @import("simulation.zig").Simulation;
const AssetManager = @import("AssetManager.zig");

/// Creates a crown entity that follows the player with the highest score.
/// If multiple players have the same score or if the highest score is zero no crowns are spawned.
/// The player entity must exist before calling this function and it must have the `Pos` and `Plr` components.
/// `offset` sets the position of the crown in relation to the leading player's position.
pub fn init(sim: *Simulation, offset: [2]i32) !void {
    var highest_player: ?ecs.entity.Entity = null;
    var highest_score: u32 = 0;
    var highest_exists: bool = false;

    var query = sim.world.query(&.{ ecs.component.Plr, ecs.component.Pos }, &.{ecs.component.Str});

    while (query.next()) |entity| {
        const plr = query.get(ecs.component.Plr) catch unreachable;

        const score = sim.meta.global_score[plr.id];

        if (score > highest_score) {
            highest_player = entity;
            highest_score = score;
            highest_exists = true;
        } else if (score == highest_score) {
            highest_exists = false;
        }
    }

    if (!highest_exists) return;

    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = .{ -100, -100 } }, // offscreen by default
        ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/crown.png"), .subpos = offset },
        ecs.component.Anm{ .animation = .Crown, .interval = 4 },
        ecs.component.Lnk{ .child = highest_player },
        ecs.component.Kng{},
    });
}

/// Updates the position of the crown. The player must have a position and be alive.
pub fn update(sim: *Simulation) !void {
    var query = sim.world.query(&.{
        ecs.component.Pos,
        ecs.component.Lnk,
        ecs.component.Kng,
    }, &.{});

    while (query.next()) |crown| {
        const pos = query.get(ecs.component.Pos) catch unreachable;
        const lnk = query.get(ecs.component.Lnk) catch unreachable;

        const player = lnk.child orelse {
            sim.world.kill(crown);
            continue;
        };

        const player_pos = sim.world.inspect(player, ecs.component.Pos) catch {
            sim.world.kill(crown);
            continue;
        };

        pos.pos = player_pos.pos;
    }
}
