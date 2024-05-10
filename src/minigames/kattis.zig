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
const Crown = @import("../crown.zig");

// Hey, nice code you got there!   (^‿^ )
// Would be a shame if someone deleted everything...   (0‿0  )

pub fn init(sim: *simulation.Simulation, timeline: input.Timeline) !void {
    const inputs = timeline.latest();
    var player_count: u8 = 0;

    // Players
    for (inputs, 0..) |inp, id| {
        if (inp.is_connected()) {
            const bitset: u32 = @truncate(sim.meta.minigame_prng.next());
            player_count += 1;

            var previous: ecs.entity.Entity = undefined;

            for (0..26) |i| {
                previous = try sim.world.spawnWith(.{
                    ecs.component.Pos{ .pos = .{ 512 - (48 + 16 * @as(i32, @intCast(i))), 32 + 28 * @as(i32, @intCast(id)) } }, // Reverse these
                    ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/kattis_testcases.png") },
                    ecs.component.Ctr{ .count = @intCast(27 - (i + 1)) }, // ID is not used anymore.
                    ecs.component.Lnk{ .child = if (i == 0) null else previous },
                });
            }

            previous = try sim.world.spawnWith(.{
                ecs.component.Ctr{ .count = 0 },
                ecs.component.Lnk{ .child = previous },
            });

            _ = try sim.world.spawnWith(.{
                ecs.component.Plr{ .id = @intCast(id) }, // Turns out this one was important (._.  )
                ecs.component.Pos{ .pos = .{ 32, 40 + 28 * @as(i32, @intCast(id)) } },
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/smash_cat.png"),
                    .w = 2,
                    .subpos = .{ -21, -10 },
                    .tint = constants.player_colors[id],
                },
                ecs.component.Anm{ .animation = Animation.SmashFall, .interval = 4, .looping = true },
                ecs.component.Ctr{ .count = 1 }, // Don't use ID field
                ecs.component.Tmr{ .ticks = bitset }, // Timer can store the solution lmao
                ecs.component.Lnk{ .child = previous },
            });
        }
    }

    // Count down.
    _ = try sim.world.spawnWith(.{
        ecs.component.Ctr{ .count = 30 * 60 },
    });

    try Crown.init(sim, .{ -6, -16 });
}

pub fn update(sim: *simulation.Simulation, timeline: input.Timeline, _: Invariables) !void {
    inputSystem(&sim.world, timeline);
    updateTextures(&sim.world, timeline);
    animator.update(&sim.world);
    try Crown.update(sim);

    var query = sim.world.query(&.{ecs.component.Ctr}, &.{ ecs.component.Plr, ecs.component.Tex, ecs.component.Lnk });
    while (query.next()) |_| {
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        if (ctr.count == 0) {
            updateRankings(sim, timeline);
            sim.meta.minigame_id = constants.minigame_scoreboard;
            return;
        }
        ctr.count -= 1;
    }
}

fn inputSystem(world: *ecs.world.World, timeline: input.Timeline) void {
    const inputs = timeline.latest();
    var query = world.query(&.{
        ecs.component.Plr,
        ecs.component.Ctr,
        ecs.component.Tmr,
        ecs.component.Lnk,
    }, &.{});
    var ended = false;

    while (query.next()) |_| {
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        const tmr = query.get(ecs.component.Tmr) catch unreachable;
        const lnk = query.get(ecs.component.Lnk) catch unreachable;
        const state = inputs[plr.id];

        const ctrlog2 = std.math.log2(ctr.count & 0x7FFFFFFF);
        var wrong = false;

        if (state.button_a == .Pressed and ctr.count & 0x80000000 == 0) {
            ctr.count <<= 1;
            wrong = ctr.count & tmr.ticks != 0;
        } else if (state.button_b == .Pressed and ctr.count & 0x80000000 == 0) {
            ctr.count <<= 1;
            wrong = ctr.count & tmr.ticks == 0;
        }

        if (wrong) {
            var timer = world.inspect(lnk.child.?, ecs.component.Ctr) catch unreachable;
            ctr.count |= 0x80000000;
            timer.count = ctrlog2 * 20;
        }
        if (ctrlog2 >= 26 and ctr.count & 0x80000000 == 0) {
            ended = true;
        }
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
    var query_p = world.query(&.{
        ecs.component.Plr,
        ecs.component.Ctr,
        ecs.component.Lnk,
    }, &.{});

    while (query_p.next()) |_| {
        const plr = query_p.get(ecs.component.Plr) catch unreachable;
        var ctr = query_p.get(ecs.component.Ctr) catch unreachable;
        var lnk = query_p.get(ecs.component.Lnk) catch unreachable;
        var pos = std.math.log2(ctr.count & 0x7FFFFFFF);

        // We didn't do an oopsie
        if (ctr.count & 0x80000000 == 0) {
            if (!(inputs[plr.id].button_a == .Pressed or inputs[plr.id].button_b == .Pressed)) continue;

            // Skip over the fail timer
            lnk = world.inspect(lnk.child.?, ecs.component.Lnk) catch unreachable;

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
        } else {
            const timer = world.inspect(lnk.child.?, ecs.component.Ctr) catch unreachable;
            lnk = world.inspect(lnk.child.?, ecs.component.Lnk) catch unreachable;

            if (timer.count > 1) {
                if (timer.count % 20 == 0) {
                    ctr.count = ((ctr.count << 1) >> 2) | 0x80000000;
                }

                timer.count = timer.count - 1;
            } else {
                ctr.count = 1;
                pos = 0;
            }

            while (lnk.child) |tick| {
                const ctr_c = world.inspect(tick, ecs.component.Ctr) catch unreachable;
                const tex_c = world.inspect(tick, ecs.component.Tex) catch unreachable;
                const lnk_c = world.inspect(tick, ecs.component.Lnk) catch unreachable;
                if (ctr_c.count <= pos) {
                    tex_c.u = 2;
                } else {
                    tex_c.u = 0;
                }

                lnk = lnk_c;
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

        const count = if (ctr.count & 0x80000000 != 0) 0 else ctr.count & 0x7FFFFFFF;
        player_scores[plr.id] = plr.id | (count << 3);
    }

    std.mem.sort(u32, &player_scores, {}, std.sort.desc(u32));

    var current_rank: u8 = 0;
    for (0..constants.max_player_count) |i| {
        if (!inputs[i].is_connected()) {
            sim.meta.minigame_placements[i] = 7;
            continue;
        }

        if (i != 0 and player_scores[i] >> 3 != player_scores[i - 1] >> 3) {
            current_rank += 1;
        }

        sim.meta.minigame_placements[player_scores[i] % 8] = current_rank;
    }
}
