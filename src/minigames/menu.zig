const std = @import("std");
const rl = @import("raylib");
const simulation = @import("../simulation.zig");
const input = @import("../input.zig");
const ecs = @import("../ecs/ecs.zig");
const constants = @import("../constants.zig");
const AssetManager = @import("../AssetManager.zig");

const Invariables = @import("../Invariables.zig");

pub fn init(sim: *simulation.Simulation, _: input.Timeline) !void {
    _ = try sim.world.spawnWith(.{
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/borggarden.png"),
            .w = constants.world_width_tiles,
            .h = constants.world_height_tiles,
        },
        ecs.component.Pos{
            .pos = .{ 0, 0 },
        },
    });

    _ = try sim.world.spawnWith(.{
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/menu.png"),
            .w = 3,
            .size = 4,
        },
        ecs.component.Pos{ .pos = .{ 164, 32 } },
    });

    _ = try sim.world.spawnWith(.{
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/menu.png"),
            .w = 6,
            .h = 3,
            .v = 3,
            .size = 2,
        },
        ecs.component.Pos{
            .pos = .{ 160, 96 + 16 },
        },
    });

    _ = try sim.world.spawnWith(.{
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/menu.png"),
            .w = 4,
            .size = 2,
            .u = 6,
            .v = 4,
        },
        ecs.component.Pos{ .pos = .{ 192, 128 } },
    });

    const resolution = try sim.world.spawnWith(.{
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/menu.png"),
            .w = 4,
            .size = 2,
            .u = 6,
            .v = 1,
        },
        ecs.component.Pos{ .pos = .{ 192, 160 } },
        ecs.component.Ctr{ .count = 1 },
    });

    _ = try sim.world.spawnWith(.{
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/menu.png"),
            .w = 6,
            .size = 2,
            .u = 0,
            .v = 1,
        },
        ecs.component.Pos{ .pos = .{ 160, 128 } },
        ecs.component.Ctr{},
        ecs.component.Lnk{ .child = resolution },
    });
}

pub fn update(sim: *simulation.Simulation, timeline: input.Timeline, _: Invariables) simulation.SimulationError!void {
    for (timeline.latest(), 0..) |inp, player_index| {
        if (!inp.is_connected()) continue;

        const horizontal = timeline.horizontal_pressed(player_index);
        const vertical = timeline.vertical_pressed(player_index);

        var query = sim.world.query(&.{
            ecs.component.Pos,
            ecs.component.Tex,
            ecs.component.Ctr,
            ecs.component.Lnk,
        }, &.{
            ecs.component.Str,
        });

        while (query.next()) |_| {
            const pos = query.get(ecs.component.Pos) catch unreachable;
            const tex = query.get(ecs.component.Tex) catch unreachable;
            const ctr = query.get(ecs.component.Ctr) catch unreachable;
            const lnk = query.get(ecs.component.Lnk) catch unreachable;

            const child_tex = sim.world.inspect(lnk.child.?, ecs.component.Tex) catch unreachable;
            const child_ctr = sim.world.inspect(lnk.child.?, ecs.component.Ctr) catch unreachable;

            if (vertical != 0) {
                const switcheroo: u32 = @intFromBool(ctr.count == 0);

                ctr.count = switcheroo;
                tex.v = switcheroo + 1;
                pos.pos = .{ 160, @intCast(128 + 32 * ctr.count) };
            } else if (ctr.count == 0 and inp.button_a == .Pressed) {
                sim.meta.minigame_id += 1;
            } else if (ctr.count != 0 and horizontal != 0) {
                const switcheroo: u32 = @intCast(horizontal + 4);

                child_ctr.count = @mod(child_ctr.count + switcheroo, 4);
                child_tex.v = child_ctr.count;

                switch (child_ctr.count) {
                    0 => rl.setWindowSize(640, 360),
                    1 => rl.setWindowSize(960, 540),
                    2 => rl.setWindowSize(1280, 720),
                    3 => rl.setWindowSize(1980, 1080),
                    else => unreachable,
                }
            }
        }
    }
}
