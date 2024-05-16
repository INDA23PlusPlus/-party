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
const morsecode_maxlen = 6;

fn assigned_pos(id: usize) @Vector(2, i32) {
    const top_left_x = 110;
    const top_left_y = 160;
    const pos: @Vector(2, i32) = [_]i32{ @intCast(80 * (id % 4) + top_left_x), @intCast(80 * (id / 4) + top_left_y) };
    return pos;
}

// TODO: better strings
const game_strings = [_][:0]const u8{
    "BABBA",
    "TEST",
    "WORD",
    "PLUSPLUS",
    "KTH",
    "DATA",
    "RAUNAK",
    "ERIK",
};

const game_strings_hash = blk: {
    var res: [game_strings.len]u64 = undefined;
    for (game_strings, 0..) |game_string, i| {
        res[i] = AssetManager.pathHash(game_string);
    }

    break :blk res;
};

fn game_string_from_hash(hash: u64) [:0]const u8 {
    for (game_strings, 0..) |game_string, i| {
        if (game_strings_hash[i] == hash) {
            return game_string;
        }
    }

    unreachable;
}

fn set_string_info(meta: *simulation.Metadata) [:0]const u8 {
    //var rand_impl = std.rand.DefaultPrng.init(@as(u64, @bitCast(std.time.milliTimestamp())));
    var prng = meta.minigame_prng;
    const num = @mod(prng.random().int(u8), game_strings.len);
    //_ = num;
    //std.debug.print("game_string: {any}\n", .{game_strings[0]});
    return game_strings[num]; // TODO: change 0 to num when polishing
}

const player_strings: [constants.max_player_count][:0]const u8 = blk: {
    var res: [constants.max_player_count][:0]const u8 = undefined;
    for (0..constants.max_player_count) |id| {
        res[id] = "Player " ++ std.fmt.comptimePrint("{}", .{id});
    }
    break :blk res;
};

pub fn init(sim: *simulation.Simulation, timeline: input.Timeline) !void {
    for (0..constants.max_player_count) |id| {
        sim.meta.minigame_placements[id] = constants.max_player_count - 1;
    }

    // space background
    _ = try sim.world.spawnWith(.{
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/morsecode_background.png"),
            .w = constants.world_width_tiles,
            .h = constants.world_height_tiles,
        },
        ecs.component.Pos{},
    });

    // morsecode table
    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = [2]i32{ 246, 108 } },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/morsetable_bitmap.png"),
            .w = constants.world_width_tiles / 2,
            .h = constants.world_height_tiles / 2,
        },
    });

    const game_string = set_string_info(&sim.meta);
    const string_info = try sim.world.spawnWith(.{
        ecs.component.Txx{
            .hash = AssetManager.pathHash(game_string),
        },
    });

    for (timeline.latest(), 0..) |inp, id| {
        if (inp.is_connected()) {
            _ = try sim.world.spawnWith(.{
                // cats
                ecs.component.Txx{
                    .hash = AssetManager.pathHash(player_strings[id]),
                    .font_size = 10,
                    .color = 0xff0066ff,
                    .subpos = .{ -10, 16 },
                },
                ecs.component.Pos{ .pos = assigned_pos(id) },
                ecs.component.Tex{
                    //.texture_hash = AssetManager.pathHash("assets/kattis.png"),
                    .texture_hash = AssetManager.pathHash("assets/cat_portrait.png"),
                    .tint = constants.player_colors[id],
                    .w = 1,
                    .h = 1,
                },
                //ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
                ecs.component.Anm{ .animation = Animation.CatPortrait, .interval = 20, .looping = true },
            });
            var button_position: @Vector(2, i32) = assigned_pos(id);
            button_position[1] += @intCast(-17);

            // data_entity cause I need it
            const data_entity = try sim.world.spawnWith(.{
                ecs.component.Ctr{ .count = 0 },
                ecs.component.Tmr{ .ticks = 0 },
                ecs.component.Lnk{ .child = string_info },
            });

            // buttons
            _ = try sim.world.spawnWith(.{
                ecs.component.Plr{ .id = @intCast(id) },
                ecs.component.Pos{ .pos = .{ button_position[0], button_position[1] } },
                ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/morsecode_buttons.png") },
                ecs.component.Ctr{ .count = 0 }, // count = bit_index, id = current letter
                ecs.component.Lnk{ .child = data_entity },
                ecs.component.Tmr{ .ticks = 0 }, // for keystroke_bitset
            });
        }
    }

    _ = try sim.world.spawnWith(.{
        ecs.component.Pos{ .pos = [2]i32{ 230, 30 } },
        ecs.component.Txx{
            .hash = AssetManager.pathHash(game_string),
            .color = 0xF4743BFF,
            .font_size = 45,
        },
    });

    // Count down.
    sim.meta.minigame_timer = 60 * 60;
}

pub fn update(sim: *simulation.Simulation, timeline: input.Timeline, _: Invariables) !void {
    //rl.drawText("Morsecode Minigame", 300, 8, 32, rl.Color.blue);
    try inputSystem(&sim.world, timeline);
    try wordSystem(&sim.world, &sim.meta);
    animator.update(&sim.world);
    try scoreSystem(&sim.meta);
}

fn scoreSystem(meta: *simulation.Metadata) !void {
    if (meta.minigame_timer <= 0) {
        std.debug.print("ending pfo: {any}\n", .{meta.minigame_placements});
        for (0..constants.max_player_count) |j| {
            if (meta.minigame_placements[j] == constants.max_player_count - 1) {
                meta.minigame_placements[j] = @as(u32, @intCast(meta.minigame_counter));
            }
        }
        std.debug.print("ending miniplaces: {any}\n", .{meta.minigame_placements});
        meta.minigame_id = constants.minigame_scoreboard;
        return;
    } else {
        meta.minigame_timer -= 1;
    }
}

fn inputSystem(world: *ecs.world.World, timeline: input.Timeline) !void {
    const inputs: input.AllPlayerButtons = timeline.latest();
    var query = world.query(&.{ ecs.component.Plr, ecs.component.Tex, ecs.component.Ctr, ecs.component.Tmr, ecs.component.Lnk }, &.{});

    while (query.next()) |_| {
        const plr = try query.get(ecs.component.Plr);
        const state = inputs[plr.id];
        var bit_index = try query.get(ecs.component.Ctr);
        var keystroke_bitset = try query.get(ecs.component.Tmr);
        //std.debug.print("plr: {any}\n", .{plr.id});
        //std.debug.print("keystroke_bitset: {any}\n\n", .{keystroke_bitset.ticks});
        var tex = query.get(ecs.component.Tex) catch unreachable;
        const lnk = query.get(ecs.component.Lnk) catch unreachable;
        var correct_letter_typed = world.inspect(lnk.child.?, ecs.component.Tmr) catch unreachable;

        if (state.is_connected()) {
            if (bit_index.count == 0 and correct_letter_typed.ticks != 0) {
                tex.u = correct_letter_typed.ticks;
            } else if (state.button_a == .Held or state.button_b == .Held) {
                tex.u = if (state.button_a == .Held) 3 else 4;
            } else {
                tex.u = 0;
            }
            if (state.button_a == .Pressed or state.button_b == .Pressed) {
                bit_index.count += if (state.button_b == .Pressed) 1 else 0;
                keystroke_bitset.ticks |= (@as(u32, 1) << @as(u5, @intCast(bit_index.count)));
                bit_index.count += 1;
            } else if (timeline.horizontal_pressed(plr.id) != 0 and bit_index.count > 0) {
                // should work as a backspace / undo
                std.debug.print("backspace\n", .{});
                correct_letter_typed.ticks = 0;
                keystroke_bitset.ticks &= ~(@as(u32, 1) << @as(u5, @intCast(bit_index.count - 1)));
                if ((bit_index.count >= 2) and (keystroke_bitset.ticks & (@as(u32, 1) << @as(u5, @intCast(bit_index.count - 2))) == 0)) {
                    bit_index.count -= 2;
                } else {
                    bit_index.count = @max(0, @as(i8, @intCast(bit_index.count)) - 1);
                }
                tex.u = 0;
            }
        }
    }
}

fn wordSystem(world: *ecs.world.World, meta: *simulation.Metadata) !void {
    var query = world.query(&.{ ecs.component.Plr, ecs.component.Lnk, ecs.component.Ctr, ecs.component.Tmr, ecs.component.Tex }, &.{});

    while (query.next()) |entity| {
        const plr = try query.get(ecs.component.Plr);
        const lnk = query.get(ecs.component.Lnk) catch unreachable;
        var ctr = query.get(ecs.component.Ctr) catch unreachable; // count = bit_index, id = current letter
        var keystrokes_bitset = query.get(ecs.component.Tmr) catch unreachable;
        //var tex = query.get(ecs.component.Tex) catch unreachable;

        var current_letter = world.inspect(lnk.child.?, ecs.component.Ctr) catch unreachable;
        const child_lnk = world.inspect(lnk.child.?, ecs.component.Lnk) catch unreachable;
        const game_string_comp = world.inspect(child_lnk.child.?, ecs.component.Txx) catch unreachable;
        const game_string = game_string_from_hash(game_string_comp.hash);
        var correct_letter_typed = world.inspect(lnk.child.?, ecs.component.Tmr) catch unreachable;

        if (ctr.count == 0) continue;

        const character: u8 = code_to_char(keystrokes_bitset.ticks);
        //std.debug.print("char: {any}\n", .{character});
        //std.debug.print("real: {any}\n\n", .{game_string[current_letter.count]});
        if (character == game_string[current_letter.count]) {
            //std.debug.print("IN\n", .{});
            ctr.count = 0;
            current_letter.count += 1;
            keystrokes_bitset.ticks = 0;
            correct_letter_typed.ticks = 1;
            if (current_letter.count == game_string.len) {
                meta.minigame_placements[meta.minigame_counter] = @intCast(plr.id);
                meta.minigame_counter += 1;
                world.kill(entity);
                std.debug.print("Player finish order: {any}\n", .{meta.minigame_placements});
                // player has finished
                // TODO: ignore this players inputs from now on
            }
        }

        if (ctr.count >= 10) {
            keystrokes_bitset.ticks = 0;
            ctr.count = 0;
            //tex.u = 2;
            correct_letter_typed.ticks = 2;
        }
    }
}

fn code_to_char(code: u32) u8 {
    return switch (code) {
        5 => 'A',
        30 => 'B',
        54 => 'C',
        14 => 'D',
        1 => 'E',
        27 => 'F',
        26 => 'G',
        15 => 'H',
        3 => 'I',
        85 => 'J',
        22 => 'K',
        29 => 'L',
        10 => 'M',
        6 => 'N',
        42 => 'O',
        53 => 'P',
        90 => 'Q',
        13 => 'R',
        7 => 'S',
        2 => 'T',
        11 => 'U',
        23 => 'V',
        21 => 'W',
        46 => 'X',
        86 => 'Y',
        58 => 'Z',
        else => '0',
    };
}
