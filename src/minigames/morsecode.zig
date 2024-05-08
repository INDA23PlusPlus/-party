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
var game_string: [:0]const u8 = undefined;
var game_string_len: usize = 20;
var current_placement: usize = 0;
var player_finish_order = [_]u32{100} ** constants.max_player_count;
var buf: [30]u8 = std.mem.zeroes([30]u8);

fn assigned_pos(id: usize) @Vector(2, i32) {
    const top_left_x = 120;
    const top_left_y = 160;
    const pos: @Vector(2, i32) = [_]i32{ @intCast(80 * (id % 4) + top_left_x), @intCast(80 * (id / 4) + top_left_y) };
    return pos;
}

// TODO: better strings
const game_strings = [_][:0]const u8{
    "BABBA",
    "TEST",
    "WORD",
};

fn set_string_info() void {
    // TODO: pick random from list
    game_string = game_strings[0];
    game_string_len = game_string.len;
    // return "plusplusparty";
}

const player_strings: [constants.max_player_count][:0]const u8 = blk: {
    var res: [constants.max_player_count][:0]const u8 = undefined;
    for (0..constants.max_player_count) |id| {
        res[id] = "Player " ++ std.fmt.comptimePrint("{}", .{id});
    }
    break :blk res;
};

pub fn init(sim: *simulation.Simulation, inputs: input.Timeline) !void {
    sim.meta.minigame_ticks_per_update = 50;
    set_string_info();

    // _ = sim;
    // jag tänker att det ska vara ett klassrum, och alla spelare är elever
    // de kommer först in i klassrummet genom en och samma rum och sedan står på angett plats
    // typ i rader. Framför varje spelare kan vi lägga dess morsecode keypresses
    // på tavlan har vi den dynamiska morse code tabellen.

    // kan inte zig, fick hårdkoda detta, help me pls
    for (inputs, 0..) |inp, id| {
        if (inp.is_connected()) {
            for (0..morsecode_maxlen) |j| {
                keystrokes[id][j] = 0;
            }
        }
    }

    for (inputs, 0..) |inp, id| {
        if (inp.is_connected()) {
            // const temp: []const u8 = std.fmt.bufPrint(&buf, "Player {}", .{id}) catch @panic("cock");
            // const temp2 = buf[0..temp.len :0];
            _ = try sim.world.spawnWith(.{
                // ecs.component.Plr{ .id = @intCast(id) }, // only use this to name the players
                ecs.component.Txt{
                    .string = player_strings[id],
                    .font_size = 10,
                    .color = 0xff0066ff,
                    .subpos = .{ 10, 20 },
                },
                ecs.component.Pos{ .pos = assigned_pos(id) },
                ecs.component.Mov{ .velocity = ecs.component.Vec2.init(0, 0) },
                ecs.component.Tex{
                    //.texture_hash = AssetManager.pathHash("assets/kattis.png"),
                    .texture_hash = AssetManager.pathHash("assets/kattis.png"),
                    .tint = constants.player_colors[id],
                },
                //ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
                ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
            });
            var button_position: @Vector(2, i32) = assigned_pos(id);
            button_position[1] += @intCast(-17);

            _ = try sim.world.spawnWith(.{
                ecs.component.Plr{ .id = @intCast(id) },
                ecs.component.Pos{ .pos = .{ button_position[0], button_position[1] } },
                ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/kattis_testcases.png") },
                //ecs.component.Ctr{ .id = @intCast(id), .count = @intCast(id + 1) },
            });
        }
    }

    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = [2]i32{ 245, 55 } },
        ecs.component.Txt{
            .string = game_string,
            // .font_size = 10,
            .color = 0x666666FF,
        },
    });

    // Count down.
    _ = try sim.world.spawnWith(.{
        ecs.component.Ctr{ .count = 30 * 60 }, // change the 30 while debugging
    });
}

pub fn update(sim: *simulation.Simulation, timeline: input.Timeline, _: Invariables) !void {
    rl.drawText("Morsecode Minigame", 300, 8, 32, rl.Color.blue);
    // rl.drawText(game_string, 300, 50, 32, rl.Color.blue);
    try inputSystem(&sim.world, timeline);
    try wordSystem(&sim.world);
    animator.update(&sim.world);

    var query = sim.world.query(&.{ecs.component.Ctr}, &.{});
    while (query.next()) |_| {
        const ctr = query.get(ecs.component.Ctr) catch unreachable;
        if (ctr.count <= 0) {
            std.debug.print("ending pfo: {any}\n", .{player_finish_order});
            for (0..constants.max_player_count) |j| {
                if (player_finish_order[j] == 100) {
                    player_finish_order[j] = @as(u32, @intCast(current_placement));
                }
            }
            sim.meta.minigame_placements = player_finish_order;
            std.debug.print("ending miniplaces: {any}\n", .{sim.meta.minigame_placements});
            sim.meta.minigame_id = 3;
            return;
        } else {
            ctr.count -= 1;
        }
    }
}

fn inputSystem(world: *ecs.world.World, timeline: input.Timeline) !void {
    const inputs: input.AllPlayerButtons = timeline.latest();
    var query = world.query(&.{ ecs.component.Plr, ecs.component.Tex }, &.{});
    while (query.next()) |_| {
        const plr = try query.get(ecs.component.Plr);
        const state = inputs[plr.id];
        var tex = query.get(ecs.component.Tex) catch unreachable;

        if (state.is_connected()) {
            if (state.button_a == .Pressed) {
                keystrokes[plr.id][typed_len[plr.id]] = 1;
                typed_len[plr.id] += 1;
                tex.u = 1;
            } else if (state.button_b == .Pressed) {
                keystrokes[plr.id][typed_len[plr.id]] = 2;
                typed_len[plr.id] += 1;
                tex.u = 2;
            } else if (timeline.vertical_pressed(plr.id) != 0) {
                keystrokes[plr.id][typed_len[plr.id]] = 3;
                typed_len[plr.id] += 1;
                tex.u = 0;
            } else if (timeline.horizontal_pressed(plr.id) != 0) {
                // should work as a backspace / undo
                typed_len[plr.id] = @max(0, @as(i8, @intCast(typed_len[plr.id])) - 1);
                keystrokes[plr.id][typed_len[plr.id]] = 0;
                tex.u = 0;
            }
        }
    }
}

fn wordSystem(world: *ecs.world.World) !void {
    _ = world;
    for (0..constants.max_player_count) |id| {
        if (typed_len[id] == 0) continue;

        if (keystrokes[id][typed_len[id] - 1] == 3) {
            const character: u8 = code_to_char(id);
            if (character == game_string[current_letter[id]]) {
                typed_len[id] = 0;
                current_letter[id] += 1;
                keystrokes[id] = .{ 0, 0, 0, 0, 0, 0 };
                if (current_letter[id] == game_string_len) {
                    // There is a small problem with this, lower ids get prioritized in this check
                    player_finish_order[current_placement] = @intCast(id);
                    current_placement += 1;
                    std.debug.print("Current placement: {any}\n", .{current_placement});
                    std.debug.print("Player finish order: {any}\n", .{player_finish_order});
                    // player has finished
                }
            } else {
                typed_len[id] = 0;
                keystrokes[id] = .{ 0, 0, 0, 0, 0, 0 };
            }
        } else if (typed_len[id] == morsecode_maxlen) {
            keystrokes[id] = .{ 0, 0, 0, 0, 0, 0 };
            typed_len[id] = 0;
        }
    }
}

fn code_to_char(id: usize) u8 {
    var a = keystrokes[id];
    var res: u8 = '0';
    if (std.mem.eql(u8, &a, &[_]u8{ 1, 2, 3, 0, 0, 0 })) {
        res = 'A';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 2, 1, 1, 1, 3, 0 })) {
        res = 'B';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 2, 1, 2, 1, 3, 0 })) {
        res = 'C';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 2, 1, 1, 3, 0, 0 })) {
        res = 'D';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 1, 3, 0, 0, 0, 0 })) {
        res = 'E';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 1, 1, 2, 1, 3, 0 })) {
        res = 'F';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 2, 2, 1, 3, 0, 0 })) {
        res = 'G';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 1, 1, 1, 1, 3, 0 })) {
        res = 'H';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 1, 1, 3, 0, 0, 0 })) {
        res = 'I';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 1, 2, 2, 2, 3, 0 })) {
        res = 'J';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 2, 1, 2, 3, 0, 0 })) {
        res = 'K';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 1, 2, 1, 1, 3, 0 })) {
        res = 'L';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 2, 2, 3, 0, 0, 0 })) {
        res = 'M';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 2, 2, 3, 0, 0, 0 })) {
        res = 'N';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 2, 2, 2, 3, 0, 0 })) {
        res = 'O';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 1, 2, 2, 1, 3, 0 })) {
        res = 'P';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 2, 2, 1, 2, 3, 0 })) {
        res = 'Q';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 1, 2, 1, 3, 0, 0 })) {
        res = 'R';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 1, 1, 1, 3, 0, 0 })) {
        res = 'S';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 2, 3, 0, 0, 0, 0 })) {
        res = 'T';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 1, 1, 2, 3, 0, 0 })) {
        res = 'U';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 1, 1, 1, 2, 3, 0 })) {
        res = 'V';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 1, 2, 2, 3, 0, 0 })) {
        res = 'W';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 2, 1, 1, 2, 3, 0 })) {
        res = 'X';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 2, 1, 2, 2, 3, 0 })) {
        res = 'Y';
    } else if (std.mem.eql(u8, &a, &[_]u8{ 2, 2, 1, 1, 3, 0 })) {
        res = 'Z';
    }
    return res;
}
