const std = @import("std");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const render = @import("../render.zig");
const input = @import("../input.zig");
const constants = @import("../constants.zig");

const AssetManager = @import("../AssetManager.zig");
const Invariables = @import("../Invariables.zig");
const Minigame = @import("Minigame.zig");

pub fn init(sim: *simulation.Simulation, _: input.Timeline) !void {
    _ = try sim.world.spawnWith(.{
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/roulette.png"),
            .w = constants.world_width_tiles,
            .h = constants.world_height_tiles,
        },
        ecs.component.Pos{},
    });

    _ = try sim.world.spawnWith(.{
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/gamewheel.png"),
            .w = 6,
            .h = 6,
        },
        ecs.component.Pos{ .pos = .{ 208, 96 } },
    });

    _ = try sim.world.spawnWith(.{
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/gamewheel.png"),
            .w = 8,
            .v = 7,
        },
        ecs.component.Pos{},
        ecs.component.Ctr{ .count = sim.meta.minigame_prng.random().int(u8) },
    });

    sim.meta.minigame_counter = 1;
}

pub fn update(sim: *simulation.Simulation, _: input.Timeline, rt: Invariables) !void {
    const minigames: u32 = @intCast(rt.minigames_list[sim.meta.minigame_id + 1 ..].len);

    if (sim.meta.minigame_timer < 15 and sim.meta.minigame_timer % sim.meta.minigame_counter == 0) {
        sim.meta.minigame_timer = 0;
        sim.meta.minigame_counter += 1;

        std.debug.print("{} {}\n", .{ sim.meta.minigame_timer, sim.meta.minigame_counter });

        var query = sim.world.query(&.{
            ecs.component.Pos,
            ecs.component.Ctr,
        }, &.{});

        while (query.next()) |_| {
            const pos = query.get(ecs.component.Pos) catch unreachable;
            const ctr = query.get(ecs.component.Ctr) catch unreachable;

            ctr.count = (ctr.count + 1) % minigames;
            pos.pos = [_]i32{ 192, 96 + @as(i32, @intCast(16 * ctr.count)) };
        }
    } else if (sim.meta.minigame_timer == 20) {
        var query = sim.world.query(&.{
            ecs.component.Ctr,
        }, &.{});

        while (query.next()) |_| {
            const ctr = query.get(ecs.component.Ctr) catch unreachable;

            sim.meta.minigame_id = ctr.count + sim.meta.minigame_id + 1;
        }
    }

    sim.meta.minigame_timer += 1;
}
