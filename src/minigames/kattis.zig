const std = @import("std");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const constants = @import("../constants.zig");
const input = @import("../input.zig");
const AssetManager = @import("../AssetManager.zig");
const animator = @import("../animation/animator.zig");
const Animation = @import("../animation/animations.zig").Animation;
const Invariables = @import("../Invariables.zig");

// Hey, nice code you got there!   (^‿^ )
// Would be a shame if someone deleted everything...   (0‿0  )

pub fn init(sim: *simulation.Simulation, timeline: input.Timeline) !void {
    const inputs = timeline.latest();
    var rng = std.rand.DefaultPrng.init(sim.meta.seed + sim.meta.ticks_elapsed);
    var player_count: u8 = 0;

    // Players
    for (inputs, 0..) |inp, id| {
        if (inp.is_connected()) {
            const bitset: u32 = @truncate(rng.next());
            std.debug.print("{b}\n", .{bitset});
            player_count += 1;
            _ = try sim.world.spawnWith(.{
                ecs.component.Plr{ .id = @intCast(id) },
                ecs.component.Pos{ .pos = .{ 16, 32 + 28 * @as(i32, @intCast(id)) } },
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/kattis.png"),
                    .tint = constants.player_colors[id],
                },
                ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
                ecs.component.Ctr{ .id = bitset, .count = 1 },
            });

            for (0..26) |i| {
                _ = try sim.world.spawnWith(.{
                    ecs.component.Pos{ .pos = .{ 48 + 16 * @as(i32, @intCast(i)), 32 + 28 * @as(i32, @intCast(id)) } },
                    ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/kattis_testcases.png") },
                    ecs.component.Ctr{ .id = @intCast(id), .count = @intCast(i + 1) },
                });
            }
        }
    }

    // Count down.
    _ = try sim.world.spawnWith(.{
        ecs.component.Ctr{ .id = 100, .count = 30 * 60 },
    });
}

pub fn update(sim: *simulation.Simulation, timeline: input.Timeline, _: Invariables) !void {
    inputSystem(&sim.world, timeline);
    updateTextures(&sim.world, timeline);
    animator.update(&sim.world);

    var query = sim.world.query(&.{ecs.component.Ctr}, &.{ ecs.component.Plr, ecs.component.Tex });
    while (query.next()) |_| {
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        if (ctr.id == 100) {
            if (ctr.count == 0) {
                updateRankings(sim, timeline);
                sim.meta.minigame_id = 3;
                return;
            } else {
                ctr.count -= 1;
            }
        }
    }
}

fn inputSystem(world: *ecs.world.World, timeline: input.Timeline) void {
    const inputs = timeline.latest();
    var query = world.query(&.{ ecs.component.Plr, ecs.component.Ctr }, &.{});
    var ended = false;

    while (query.next()) |_| {
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        const state = inputs[plr.id];
        var wrong = false;

        if (state.button_a == .Pressed) {
            ctr.count <<= 1;
            wrong = ctr.count & ctr.id != 0;
        } else if (state.button_b == .Pressed) {
            ctr.count <<= 1;
            wrong = ctr.count & ctr.id == 0;
        }

        if (wrong) ctr.count = 1;
        if (std.math.log2(ctr.count) >= 26) ended = true;
    }

    if (ended) {
        var query_c = world.query(&.{ecs.component.Ctr}, &.{ ecs.component.Plr, ecs.component.Tex });
        while (query_c.next()) |_| {
            const ctr = query_c.get(ecs.component.Ctr) catch unreachable;
            if (ctr.id == 100) {
                ctr.count = 0;
            }
        }
    }
}

fn updateTextures(world: *ecs.world.World, timeline: input.Timeline) void {
    const inputs = timeline.latest();
    var query_p = world.query(&.{ ecs.component.Plr, ecs.component.Ctr }, &.{});

    while (query_p.next()) |_| {
        const plr = query_p.get(ecs.component.Plr) catch unreachable;
        if (!(inputs[plr.id].button_a == .Pressed or inputs[plr.id].button_b == .Pressed)) continue;

        const pctr = query_p.get(ecs.component.Ctr) catch unreachable;

        var query_c = world.query(&.{ ecs.component.Ctr, ecs.component.Tex }, &.{ecs.component.Plr});
        while (query_c.next()) |_| {
            const ctr = query_c.get(ecs.component.Ctr) catch unreachable;
            var tex = query_c.get(ecs.component.Tex) catch unreachable;
            if (ctr.id == plr.id and ctr.count <= std.math.log2(pctr.count)) {
                tex.u = 1;
            } else if (ctr.id == plr.id) {
                tex.u = 0;
            }
        }
    }
}

fn updateRankings(sim: *simulation.Simulation, timeline: input.Timeline) void {
    var player_scores = [_]u32{0} ** constants.max_player_count;
    const inputs = timeline.latest();

    var query = sim.world.query(&.{ ecs.component.Plr, ecs.component.Ctr }, &.{});

    while (query.next()) |_| {
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const ctr = query.get(ecs.component.Ctr) catch unreachable;

        player_scores[plr.id] = (@as(u32, 8) << @truncate(ctr.count)) + plr.id;
    }

    std.mem.sort(u32, &player_scores, {}, std.sort.desc(u32));

    var current_rank: u8 = 0;
    for (0..constants.max_player_count) |i| {
        if (!inputs[i].is_connected()) continue;

        if (i != 0 and player_scores[i] != player_scores[i - 1]) {
            current_rank += 1;
        }

        sim.meta.minigame_placements[player_scores[i] % 8] += 8 - current_rank;
    }
}
