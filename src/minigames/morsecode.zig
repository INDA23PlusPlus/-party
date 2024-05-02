const std = @import("std");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const input = @import("../input.zig");
const AssetManager = @import("../AssetManager.zig");
const Invariables = @import("../Invariables.zig");
const constants = @import("../constants.zig");
const Animation = @import("../animation/animations.zig").Animation;
const animator = @import("../animation/animator.zig");

// all morse characters are less than 8 long
// 1 for * , 2 for -, 0 otherwise, could be done with bitmasks if we choose to not have a "new_word" key
//var keystrokes: [constants.max_player_count][8]u8 = undefined;
//std.mem.zero(keystrokes[0..]);
const morsecode_maxlen = 6;
var keystrokes: [constants.max_player_count][morsecode_maxlen]u8 = undefined;
var typed_len = std.mem.zeroes([constants.max_player_count]u8);
var current_letter = std.mem.zeroes([constants.max_player_count]u8);
var game_string: []const u8 = undefined;
var game_string_len: usize = 20;
var current_placement: usize = 0;
var player_finish_order: [constants.max_player_count]u32 = [constants.max_player_count]u32{ undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined };
var buf: [30]u8 = std.mem.zeroes([30]u8);

fn assigned_pos(id: usize) @Vector(2, i32) {
    const top_left_x = 120;
    const top_left_y = 160;
    const pos: @Vector(2, i32) = [_]i32{ @intCast(80 * (id % 4) + top_left_x), @intCast(80 * (id / 4) + top_left_y) };
    return pos;
}

fn set_string_info() void {
    // TODO: generate a random string for gameplay
    game_string = "BABBA";
    game_string_len = game_string.len;
    // return "plusplusparty";
}

pub fn init(sim: *simulation.Simulation, _: input.Timeline) !void {
    sim.meta.minigame_ticks_per_update = 50;
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
    }

    for (0..constants.max_player_count) |id| {
        // std.debug.print("{any}", .{buf});
        std.debug.print("{any}", .{id});
        const temp: []const u8 = std.fmt.bufPrint(&buf, "Player {}", .{id}) catch @panic("cock");
        const temp2 = buf[0..temp.len :0];
        _ = try sim.world.spawnWith(.{
            // ecs.component.Plr{ .id = @intCast(id) }, // only use this to name the players
            ecs.component.Txt{
                .string = temp2,
                // .string = "Player x",
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
        var button_position: @Vector(2, i32) = assigned_pos(id);
        // button_position[0] += @intCast(-10);
        button_position[1] += @intCast(-17);

        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = @intCast(id) },
            ecs.component.Pos{ .pos = .{ button_position[0], button_position[1] } },
            ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/kattis_testcases.png") },
            ecs.component.Ctr{ .id = @intCast(id), .count = @intCast(id + 1) },
        });
    }
}

pub fn update(sim: *simulation.Simulation, timeline: input.Timeline, _: Invariables) !void {
    rl.drawText("Morsecode Minigame", 300, 8, 32, rl.Color.blue);
    // rl.drawText(game_string, 300, 50, 32, rl.Color.blue);
    // try inputSystem(&sim.world, timeline.latest());
    std.debug.print("Current placement: {any}\n", .{current_placement});
    try inputSystem(&sim.world, timeline);
    try wordSystem(&sim.world);
    animator.update(&sim.world);
    if (current_placement == constants.max_player_count) {
        // everyone should be finished
        for (0..constants.max_player_count) |rank| {
            sim.meta.score[player_finish_order[rank]] = 20 - @as(u32, @intCast(rank)) * 2;
        }
    }
}

fn inputSystem(world: *ecs.world.World, timeline: input.Timeline) !void {
    const inputs: input.AllPlayerButtons = timeline.latest();
    std.debug.print("{any}\n", .{keystrokes[0]});
    std.debug.print("{any}\n", .{keystrokes[1]});
    var query = world.query(&.{ ecs.component.Plr, ecs.component.Tex }, &.{});
    while (query.next()) |_| {
        const plr = try query.get(ecs.component.Plr);
        const state = inputs[plr.id];
        var tex = query.get(ecs.component.Tex) catch unreachable;
        // std.debug.print("{any}\n", .{state});
        if (state.is_connected()) {
            // std.debug.print("typed len: {}, id: {}\n", .{ typed_len[plr.id], plr.id });
            if (state.button_a.is_down()) {
                keystrokes[plr.id][typed_len[plr.id]] = 1;
                typed_len[plr.id] += 1;
                tex.u = 1;
            } else if (state.button_b.is_down()) {
                keystrokes[plr.id][typed_len[plr.id]] = 2;
                typed_len[plr.id] += 1;
                tex.u = 2;
                if (typed_len[plr.id] == morsecode_maxlen) typed_len[plr.id] = 0; // TODO: remove this when wordSystem added
            } else if (timeline.vertical_pressed(plr.id) != 0) {
                keystrokes[plr.id][typed_len[plr.id]] = 3;
                typed_len[plr.id] += 1;
                tex.u = 0;
            } else if (timeline.vertical_pressed(plr.id) != 0) {
                // should work as a backspace / undo
                typed_len[plr.id] = @max(0, typed_len[plr.id] - 1);
                keystrokes[plr.id][typed_len[plr.id]] = 0;
                tex.u = 0;
            }
        }
    }
}

fn code_to_char(id: usize) u8 {
    //
    // _ = a;
    var a = keystrokes[id];
    var res: u8 = 0;
    if (std.mem.eql(u8, &a, &[_]u8{ 1, 2, 3, 0, 0, 0 })) {
        res = @intCast('A' - 'A' + 1);
    } else if (std.mem.eql(u8, &a, &[_]u8{ 2, 1, 1, 1, 3, 0 })) {
        res = @intCast('B' - 'A' + 1);
    }
    // TODO finish the rest of this conversion
    return res;
}

fn wordSystem(world: *ecs.world.World) !void {
    _ = world;
    for (0..constants.max_player_count) |id| {
        const character: u8 = code_to_char(id);
        if (character != 0) {
            // TODO: go into this forloop iff the end of character button has been typed
            typed_len[id] = 0;
            current_letter[id] += 1;
            keystrokes[id] = .{ 0, 0, 0, 0, 0, 0 };
            // TODO: check that the typed letter is the correct one, not just any letter
            if (current_letter[id] == game_string_len) {
                // There is a small problem with this, lower ids get prioritized in this check
                player_finish_order[current_placement] = @intCast(id);
                current_placement += 1;
                // player has finished
            }
        }
    }
}
