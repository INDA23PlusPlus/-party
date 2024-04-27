const std = @import("std");
const rl = @import("raylib");
const simulation = @import("../simulation.zig");
const input = @import("../input.zig");
const ecs = @import("../ecs/ecs.zig");
const constants = @import("../constants.zig");
const AssetManager = @import("../AssetManager.zig");

const Invariables = @import("../Invariables.zig");

var menu_items: [2]ecs.entity.Entity = undefined;

var selected: i8 = 0;
var current_resolution: i8 = 0;

const resolution_strings: [4][:0]const u8 = .{
    "Resolution: 640 x 360",
    "Resolution: 960 x 540",
    "Resolution: 1280 x 720",
    "Resolution: 1920 x 1080",
};

pub fn init(sim: *simulation.Simulation, _: []const input.InputState) simulation.SimulationError!void {
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
        ecs.component.Txt{ .string = "++Party", .color = 0x00FF99FF, .font_size = 72 },
        ecs.component.Pos{ .pos = .{ 256, 36 } },
    });

    _ = try sim.world.spawnWith(.{
        ecs.component.Txt{ .string = "ESC to EXIT", .color = 0xFFAA00FF, .font_size = 48 },
        ecs.component.Pos{ .pos = .{ 256, 240 } },
    });

    const item0 = try sim.world.spawnWith(.{
        ecs.component.Txt{ .string = "START!", .color = 0xDE3163FF, .font_size = 48 },
        ecs.component.Pos{ .pos = .{ 256, 96 } },
    });

    const item1 = try sim.world.spawnWith(.{
        ecs.component.Txt{ .string = resolution_strings[@intCast(current_resolution)], .color = 0x000000FF, .font_size = 36 },
        ecs.component.Pos{ .pos = .{ 256, 167 } },
    });

    // Save identifiers
    menu_items = .{
        item0,
        item1,
    };
}

pub fn update(sim: *simulation.Simulation, inputs: []const input.InputState, _: Invariables) simulation.SimulationError!void {
    try handleInputs(sim, &inputs[inputs.len - 1]);
}

fn handleInputs(sim: *simulation.Simulation, inputs: *const input.InputState) !void {
    for (inputs) |inp| {
        if (inp.is_connected) {
            if (inp.button_down.pressed()) {
                const previous = selected;
                selected = @mod(selected + 1, 2);
                try changeSelection(sim, selected, previous);
            }
            if (inp.button_up.pressed()) {
                const previous = selected;
                selected = @mod(selected - 1, 2);
                try changeSelection(sim, selected, previous);
            }
            if (inp.button_right.pressed() and selected == 1) {
                current_resolution = @mod(current_resolution + 1, 4);
                try changeResolution(sim, current_resolution);
            }
            if (inp.button_left.pressed() and selected == 1) {
                current_resolution = @mod(current_resolution - 1, 4);
                try changeResolution(sim, current_resolution);
            }
            if (inp.button_b.pressed() and selected == 0) {
                sim.meta.minigame_id = 1; // Send to lobby
            }
        }
    }
}

fn changeSelection(sim: *simulation.Simulation, cur: i8, prev: i8) !void {
    var prev_txt_comp = try sim.world.inspect(menu_items[@intCast(prev)], ecs.component.Txt);
    var cur_txt_comp = try sim.world.inspect(menu_items[@intCast(cur)], ecs.component.Txt);

    prev_txt_comp.color = 0x000000FF;
    cur_txt_comp.color = 0xDE3163FF;
}

fn changeResolution(sim: *simulation.Simulation, cur: i8) !void {
    var txt_comp = try sim.world.inspect(menu_items[@intCast(selected)], ecs.component.Txt);
    txt_comp.string = resolution_strings[@intCast(cur)];

    setWindowSize();
}

fn setWindowSize() void {
    switch (current_resolution) {
        0 => rl.setWindowSize(640, 360),
        1 => rl.setWindowSize(960, 540),
        2 => rl.setWindowSize(1280, 720),
        3 => rl.setWindowSize(1980, 1080),
        else => unreachable,
    }
}
