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
            player_count += 1;

            var ticks: [26]ecs.entity.Entity = undefined;

            for (0..26) |i| {
                ticks[i] = try sim.world.spawnWith(.{
                    ecs.component.Pos{ .pos = .{ 512 - (48 + 16 * @as(i32, @intCast(i))), 32 + 28 * @as(i32, @intCast(id)) } }, // Reverse these
                    ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/kattis_testcases.png") },
                    ecs.component.Ctr{ .count = @intCast(27 - (i + 1)) }, // ID is not used anymore.
                    ecs.component.Lnk{ .child = if (i == 0) null else ticks[i - 1] },
                });
            }

            _ = try sim.world.spawnWith(.{
                ecs.component.Plr{ .id = @intCast(id) }, // Turns out this one was important (._.  )
                ecs.component.Pos{ .pos = .{ 16, 32 + 28 * @as(i32, @intCast(id)) } },
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/kattis.png"),
                    .tint = constants.player_colors[id],
                },
                ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
                ecs.component.Ctr{ .count = 1 }, // Don't use ID field
                ecs.component.Tmr{ .ticks = bitset }, // Timer can store the solution lmao
                ecs.component.Lnk{ .child = ticks[ticks.len - 1] },
            });
        }
    }

    // Count down.
    _ = try sim.world.spawnWith(.{
        ecs.component.Ctr{ .count = 30 * 60 },
    });
}

pub fn update(sim: *simulation.Simulation, timeline: input.Timeline, _: Invariables) !void {
    inputSystem(&sim.world, timeline);
    updateTextures(&sim.world, timeline);
    animator.update(&sim.world);

    var query = sim.world.query(&.{ecs.component.Ctr}, &.{ ecs.component.Plr, ecs.component.Tex });
    while (query.next()) |_| {
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        if (ctr.count == 0) {
            updateRankings(sim, timeline);
            sim.meta.minigame_id = 3;
            return;
        } else {
            ctr.count -= 1;
        }
    }
}

fn inputSystem(world: *ecs.world.World, timeline: input.Timeline) void {
    const inputs = timeline.latest();
    var query = world.query(&.{ ecs.component.Plr, ecs.component.Ctr, ecs.component.Tmr }, &.{});
    var ended = false;

    while (query.next()) |_| {
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        const tmr = query.get(ecs.component.Tmr) catch unreachable;
        const state = inputs[plr.id];
        var wrong = false;

        if (state.button_a == .Pressed) {
            ctr.count <<= 1;
            wrong = ctr.count & tmr.ticks != 0;
        } else if (state.button_b == .Pressed) {
            ctr.count <<= 1;
            wrong = ctr.count & tmr.ticks == 0;
        }

        if (wrong) ctr.count = 1;
        if (std.math.log2(ctr.count) >= 26) ended = true;
    }

    if (ended) {
        var query_c = world.query(&.{ecs.component.Ctr}, &.{ ecs.component.Plr, ecs.component.Tex });
        while (query_c.next()) |_| {
            const ctr = query_c.get(ecs.component.Ctr) catch unreachable;
            ctr.count = 0;
        }
    }
}

fn updateTextures(world: *ecs.world.World, timeline: input.Timeline) void {
    const inputs = timeline.latest();
    var query_p = world.query(&.{ ecs.component.Plr, ecs.component.Ctr, ecs.component.Lnk }, &.{});

    while (query_p.next()) |_| {
        const plr = query_p.get(ecs.component.Plr) catch unreachable;
        if (!(inputs[plr.id].button_a == .Pressed or inputs[plr.id].button_b == .Pressed)) continue;
        const ctr = query_p.get(ecs.component.Ctr) catch unreachable;
        var lnk = query_p.get(ecs.component.Lnk) catch unreachable;

        const pos = std.math.log2(ctr.count);

        while (lnk.child) |tick| {
            const ctr_c = world.inspect(tick, ecs.component.Ctr) catch unreachable;
            const tex_c = world.inspect(tick, ecs.component.Tex) catch unreachable;
            const lnk_c = world.inspect(tick, ecs.component.Lnk) catch unreachable;
            if (ctr_c.count <= pos) {
                tex_c.u = 1;
            } else {
                tex_c.u = 0;
            }

            lnk = lnk_c;
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

        player_scores[plr.id] = plr.id | ctr.count << 3;
    }

    std.mem.sort(u32, &player_scores, {}, std.sort.desc(u32));

    var current_rank: u8 = 1;
    for (0..constants.max_player_count) |i| {
        if (!inputs[i].is_connected()) continue;

        if (i != 0 and player_scores[i] >> 3 != player_scores[i - 1] >> 3) {
            current_rank += 1;
        }

        sim.meta.minigame_placements[player_scores[i] % 8] = current_rank;
    }
}
