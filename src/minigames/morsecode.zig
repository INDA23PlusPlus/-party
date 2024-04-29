const std = @import("std");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const AssetManager = @import("../AssetManager.zig");
const Invariables = @import("../Invariables.zig");
const constants = @import("../constants.zig");
const Animation = @import("../animation/animations.zig").Animation;
const animator = @import("../animation/animator.zig");
const input = @import("../input.zig");

// all morse characters are less than 8 long
// 1 for * , 2 for -, 0 otherwise, could be done with bitmasks if we choose to not have a "new_word" key
//var keystrokes: [constants.max_player_count][8]u8 = undefined;
//std.mem.zero(keystrokes[0..]);
const morsecode_maxlen = 5;
var keystrokes: [constants.max_player_count][morsecode_maxlen]u8 = undefined;
var typed_len = std.mem.zeroes([constants.max_player_count]u8);
var current_letter: [constants.max_player_count][20]u8 = undefined;
var game_string: []const u8 = undefined;
var game_string_len: usize = 20;

fn assigned_pos(id: usize) @Vector(2, i32) {
    const top_left_x = 120;
    const top_left_y = 160;
    const pos: @Vector(2, i32) = [_]i32{ @intCast(80 * (id % 4) + top_left_x), @intCast(80 * (id / 4) + top_left_y) };
    return pos;
}

fn set_string_info() void {
    // TODO: generate a random string for gameplay
    game_string = "plusplusparty";
    game_string_len = game_string.len;
    // return "plusplusparty";
}

pub fn init(sim: *simulation.Simulation, _: []const input.InputState) !void {
    sim.meta.minigame_ticks_per_update = 8;
    set_string_info();
    // _ = sim;
    // jag tänker att det ska vara ett klassrum, och alla spelare är elever
    // de kommer först in i klassrummet genom en och samma rum och sedan står på angett plats
    // typ i rader. Framför varje spelare kan vi lägga dess morsecode keypresses
    // på tavlan har vi den dynamiska morse code tabellen.

    // kan inte zig, fick hårdkoda detta, help me pls
    for (0..constants.max_player_count) |id| {
        for (0..morsecode_maxlen) |j| {
            keystrokes[id][j] = 0;
        }
        for (0..game_string_len) |j| {
            current_letter[id][j] = 0;
        }
    }

    for (0..constants.max_player_count) |id| {
        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = @intCast(id) },
            ecs.component.Txt{
                .string = "Player x",
                .font_size = 10,
                .color = 0xff0066ff,
                .subpos = .{ 10, 20 },
            },
            ecs.component.Pos{ .pos = assigned_pos(id) },
            ecs.component.Mov{ .velocity = ecs.component.Vec2.init(0, 0) },
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/kattis.png"),
                .tint = constants.player_colors[id],
            },
            ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
            // animations för spelarna?
        });
    }
}

pub fn update(sim: *simulation.Simulation, inputs: []const input.InputState, _: Invariables) !void {
    rl.drawText("Morsecode Minigame", 64, 8, 32, rl.Color.blue);
    try inputSystem(&sim.world, &inputs[inputs.len - 1]);
    // try wordSystem(&sim.world);
    animator.update(&sim.world);
}

fn inputSystem(world: *ecs.world.World, inputs: *const input.InputState) !void {
    var query = world.query(&.{ecs.component.Plr}, &.{});
    while (query.next()) |_| {
        const plr = try query.get(ecs.component.Plr);
        const state = inputs[plr.id];
        if (state.is_connected) {
            if (state.button_a.is_down) {
                keystrokes[plr.id][typed_len[plr.id]] = 1;
                typed_len[plr.id] += 1;
                if (typed_len[plr.id] > morsecode_maxlen) typed_len[plr.id] = 0; // TODO: remove this when wordSystem added
            } else if (state.button_b.is_down) {
                keystrokes[plr.id][typed_len[plr.id]] = 2;
                typed_len[plr.id] += 1;
                if (typed_len[plr.id] > morsecode_maxlen) typed_len[plr.id] = 0; // TODO: remove this when wordSystem added
            }
            // TODO: add support for end of character (maybe)
        }
    }
}

fn code_to_char(id: usize) u8 {
    //
    // _ = a;
    var a = &keystrokes[id];
    var res: u8 = 0;
    if (std.mem.eql(u8, &a, &[_]u8{ 1, 2, 0, 0, 0 })) {
        res = @intCast('A' - 'A' + 1);
    } else if (std.mem.eql(u8, &a, &[_]u8{ 2, 1, 1, 1, 0 })) {
        res = @intCast('B' - 'A' + 1);
    }
    return res;
}

fn wordSystem(world: *ecs.world.World) !void {
    _ = world;
    for (0..constants.max_player_count) |id| {
        const character: u8 = code_to_char(id);
        if (character != 0) {
            typed_len[id] = 0;
            current_letter += 1;
            keystrokes[id] = .{ 0, 0, 0, 0, 0 };
            // TODO: check for all keystrokes arrays: equals a morse character ?
            // in which case:
            // go to next word if possible, else give player score
            if (current_letter == game_string_len) {
                // player has finished
                // TODO: add score to metadata, based on time taken
            }
        }
    }
}
