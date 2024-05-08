const std = @import("std");
const root = @import("root");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const render = @import("../render.zig");
const input = @import("../input.zig");

const AssetManager = @import("../AssetManager.zig");
const Invariables = @import("../Invariables.zig");
const Minigame = @import("Minigame.zig");

const constants = @import("../constants.zig");

const main_ctr_id = 0;
const handle_ctr_id = 1;
const waiting = std.math.maxInt(u32);

const title_id = std.math.maxInt(u32);

pub fn init(_: *simulation.Simulation, _: input.Timeline) !void {}

fn setup(sim: *simulation.Simulation, available_minigames: []const Minigame) !void {
    const pseudo = sim.meta.minigame_prng.next();
    const random_handle_start = pseudo % available_minigames.len;
    _ = try sim.world.spawnWith(.{
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/roulette.png"),
            .w = constants.world_width_tiles,
            .h = constants.world_height_tiles,
        },
        ecs.component.Pos{
            .pos = .{ 0, 0 },
        },
    });
    _ = try sim.world.spawnWith(.{ecs.component.Ctr{
        .id = main_ctr_id,
        .count = waiting,
    }});
    _ = try sim.world.spawnWith(.{ecs.component.Ctr{
        .id = handle_ctr_id,
        .count = @truncate(random_handle_start),
    }});

    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = .{ 256, 40 } },
        ecs.component.Plr{ // Not really a player, Too bad! I want a u32.
            .id = title_id,
        },
        ecs.component.Txt{
            .string = "Press A/B to spin!",
            .color = 0x00FF99FF,
            .subpos = .{ 0, 0 },
            .font_size = 24,
        },
    });

    for (available_minigames, 0..) |minigame, i| {
        _ = try sim.world.spawnWith(.{
            ecs.component.Pos{ .pos = .{ 256, 90 + @as(i32, @intCast(i)) * 15 } },
            ecs.component.Plr{ // Not really a player, Too bad! I want a u32.
                .id = @truncate(i),
            },
            ecs.component.Txt{
                .string = minigame.name,
                .color = 0x666666FF,
                .subpos = .{ 0, 0 },
                .font_size = 18,
            },
        });
    }
}

pub fn update(sim: *simulation.Simulation, timeline: input.Timeline, rt: Invariables) !void {
    const inputs = timeline.latest();
    const available_minigames = rt.minigames_list[sim.meta.minigame_id + 1 ..];

    var query = sim.world.query(&.{ecs.component.Ctr}, &.{});
    var dummy = ecs.component.Ctr{ .id = 0, .count = 0 };
    var main_ctr: *ecs.component.Ctr = &dummy;
    var handle_ctr: *ecs.component.Ctr = &dummy;
    while (query.next()) |_| {
        const ctr = try query.get(ecs.component.Ctr);
        if (ctr.id == main_ctr_id) {
            main_ctr = ctr;
        } else if (ctr.id == handle_ctr_id) {
            handle_ctr = ctr;
        }
    }
    if (main_ctr == &dummy or handle_ctr == &dummy) {
        try setup(sim, available_minigames);
        return;
    }

    for (inputs) |inp| {
        if (inp.button_a == .Pressed or inp.button_b == .Pressed) {
            if (main_ctr.count == waiting) {
                main_ctr.count = 500;
            }
            break;
        }
    }

    var handle_slowness: u32 = 5;
    if (main_ctr.count < 200) {
        handle_slowness = 40;
    } else if (main_ctr.count < 300) {
        handle_slowness = 20;
    } else if (main_ctr.count < 400) {
        handle_slowness = 10;
    }

    if (main_ctr.count > 100 and sim.meta.ticks_elapsed % handle_slowness == 0) {
        const g = (handle_ctr.count + 1) % available_minigames.len;
        handle_ctr.count = @truncate(g);
    }

    if (main_ctr.count > 0 and main_ctr.count != waiting) {
        main_ctr.count -= 1;
    } else if (main_ctr.count == 0) {
        std.debug.print("gamewheel should switch minigame\n", .{});
        const next_game = sim.meta.minigame_id + handle_ctr.count + 1;
        if (next_game < rt.minigames_list.len) {
            sim.meta.minigame_id = next_game;
        }
    }

    var query_texts = sim.world.query(&.{ ecs.component.Plr, ecs.component.Txt }, &.{});
    while (query_texts.next()) |_| {
        const plr = try query_texts.get(ecs.component.Plr);
        const txt = try query_texts.get(ecs.component.Txt);
        if (plr.id == title_id) {
            if (main_ctr.count != waiting) {
                txt.string = "Spinning...";
            }
        } else if (plr.id == handle_ctr.count) {
            txt.color = 0xDD6666FF;
        } else {
            txt.color = 0x666666FF;
        }
    }
}
