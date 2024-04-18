const std = @import("std");
const rl = @import("raylib");
const simulation = @import("../simulation.zig");
const input = @import("../input.zig");
const ecs = @import("../ecs/ecs.zig");

const Allocator = std.mem.Allocator;

var menu_items: [6]ecs.entity.Entity = undefined;
var selected: i8 = 0;
var res: i8 = 0;

pub fn init(sim: *simulation.Simulation, inputs: *const input.InputState) simulation.SimulationError!void {
    _ = inputs;

    const item0 = try sim.world.spawnWith(.{
        ecs.component.Txt{ .string = "START!", .color = 0xDE3163FF, .font_size = 48 },
        ecs.component.Pos{ .pos = .{ 256, 96 } },
    });
    const item1 = try sim.world.spawnWith(.{
        ecs.component.Txt{ .string = "EXIT :c", .color = 0x000000FF, .font_size = 48 },
        ecs.component.Pos{ .pos = .{ 256, 192 } },
    });

    const item2 = try sim.world.spawnWith(.{
        ecs.component.Txt{ .string = "Resolution: 640 x 360", .color = 0x000000FF, .font_size = 48 },
        ecs.component.Pos{ .pos = .{ 256, 144 } },
    });

    const item3 = try sim.world.spawnWith(.{
        ecs.component.Txt{ .string = "Resolution: 960 x 540", .color = 0x000000FF, .font_size = 48, .draw = false },
        ecs.component.Pos{ .pos = .{ 256, 144 } },
    });

    const item4 = try sim.world.spawnWith(.{
        ecs.component.Txt{ .string = "Resolution: 1280 x 720", .color = 0x000000FF, .font_size = 48, .draw = false },
        ecs.component.Pos{ .pos = .{ 256, 144 } },
    });

    const item5 = try sim.world.spawnWith(.{
        ecs.component.Txt{ .string = "Resolution: 1980 x 1080", .color = 0x000000FF, .font_size = 48, .draw = false },
        ecs.component.Pos{ .pos = .{ 256, 144 } },
    });

    // Save identifiers
    menu_items = .{
        item0,
        item1,
        item2,
        item3,
        item4,
        item5,
    };
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState, arena: Allocator) simulation.SimulationError!void {
    _ = arena;

    for (inputs) |inp| {
        if (inp.is_connected) {
            if (inp.down.pressed()) selected = @mod(selected + 1, 3);
            if (inp.up.pressed()) selected = @mod(selected - 1, 3);
            if (inp.right.pressed() and selected == 1) {
                const prev_res = res;
                res = @mod(res + 1, 4);

                var prev_txt_comp = try sim.world.inspect(menu_items[@as(usize, @intCast(prev_res)) + 2], ecs.component.Txt);
                var cur_txt_comp = try sim.world.inspect(menu_items[@as(usize, @intCast(res)) + 2], ecs.component.Txt);
                prev_txt_comp.color = 0x000000FF;
                prev_txt_comp.draw = false;

                cur_txt_comp.color = 0xDE3163FF;
                cur_txt_comp.draw = true;
            }
            if (inp.left.pressed() and selected == 1) {
                const prev_res = res;
                res = @mod(res - 1, 4);

                var prev_txt_comp = try sim.world.inspect(menu_items[@as(usize, @intCast(prev_res)) + 2], ecs.component.Txt);
                var cur_txt_comp = try sim.world.inspect(menu_items[@as(usize, @intCast(res)) + 2], ecs.component.Txt);
                prev_txt_comp.color = 0x000000FF;
                prev_txt_comp.draw = false;

                cur_txt_comp.color = 0xDE3163FF;
                cur_txt_comp.draw = true;
            }
        }
    }
}

fn setWindowSize() void {
    switch (res) {
        0 => rl.setWindowSize(640, 360),
        1 => rl.setWindowSize(960, 540),
        2 => rl.setWindowSize(1280, 720),
        3 => rl.setWindowSize(1980, 1080),
    }
}
