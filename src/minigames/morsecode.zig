const std = @import("std");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const AssetManager = @import("../AssetManager.zig");
const constants = @import("../constants.zig");
const input = @import("../input.zig");

// all morse characters are less than 8 long
// 1 for * , 2 for -, 0 otherwise
var keystrokes: [constants.max_player_count][8]u8 = [][]u8{.{0}};

fn assigned_pos(id: usize) @Vector(2, i32) {
    const top_left_x = 120;
    const top_left_y = 160;
    const pos = @Vector(2, i32){ @intCast(80 * (id % 4) + top_left_x), @intCast(80 * (id / 4) + top_left_y) };
    return pos;
}

pub fn init(sim: *simulation.Simulation) !void {
    // _ = sim;
    // jag tänker att det ska vara ett klassrum, och alla spelare är elever
    // de kommer först in i klassrummet genom en och samma rum och sedan står på angett plats
    // typ i rader. Framför varje spelare kan vi lägga dess morsecode keypresses
    // på tavlan har vi den dynamiska morse code tabellen.
    for (0..constants.max_player_count) |id| {
        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = id },
            ecs.component.Txt{ .string = "Player x" },
            ecs.component.Pos{ .pos = assigned_pos(id) },
            ecs.component.Mov{ .velocity = ecs.component.Vec2.init(0, 0) },
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/kattis.png"),
                .tint = constants.player_colors[id],
            },
            // animations för spelarna?
        });
    }
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState, arena: std.mem.Allocator) !void {
    _ = arena;
    rl.drawText("This is a new minigame", 64, 8, 32, rl.Color.blue);
    _ = inputs;
    _ = sim;
}
