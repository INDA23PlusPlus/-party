const std = @import("std");
const rl = @import("raylib");
const ecs = @import("../ecs/ecs.zig");
const simulation = @import("../simulation.zig");
const input = @import("../input.zig");
const AssetManager = @import("../AssetManager.zig");
const animator = @import("../animation/animator.zig");
const Animation = @import("../animation/animations.zig").Animation;
const constants = @import("../constants.zig");
const Invariables = @import("../Invariables.zig");

const test_cases_count = 14;

var current_score = [_]u8{0} ** constants.max_player_count;
var best_score = [_]u8{0} ** constants.max_player_count;
var waiting = [_]bool{true} ** constants.max_player_count;
var completed_tcs = [_]std.bit_set.StaticBitSet(test_cases_count){std.bit_set.StaticBitSet(test_cases_count).initEmpty()} ** constants.max_player_count;
var correct_tcs = [_]std.bit_set.StaticBitSet(test_cases_count){std.bit_set.StaticBitSet(test_cases_count).initEmpty()} ** constants.max_player_count;

// Game over, (time limit exceeded)
var tle = false;

pub fn init(sim: *simulation.Simulation, _: *const input.InputState) !void {
    
    //Init correct testcases
    var rng = std.rand.DefaultPrng.init(sim.meta.seed + sim.meta.ticks_elapsed);

    for (0..constants.max_player_count) |id| {
        for (0..test_cases_count) |test_case| {
            correct_tcs[id].setValue(test_case, @mod(rng.next(), 2) == 1);
        }
    }

    // Init world
    for (0..8) |id| {

        const plr_collumn = 4 + 3 * @as(i32, @intCast(id));

        // PLayer
        _ = try sim.world.spawnWith(.{
            ecs.component.Plr{ .id = @intCast(id) },
            ecs.component.Pos{ .pos = [_]i32{ 16 * plr_collumn, 16 * 16 } },
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/kattis.png"),
                .tint = constants.player_colors[id],
            },
            ecs.component.Anm{ .animation = Animation.KattisIdle, .interval = 16, .looping = true },
            ecs.component.Ctr{
                .id = @intCast(id),
                .counter = 0
            },
        });

        // Player testcases
        for (0..test_cases_count) |testcase| {
            _ = try sim.world.spawnWith(.{
                ecs.component.Pos{ .pos = [_]i32{ 16 * (plr_collumn + 1), 16 * (15 - @as(i32, @intCast(testcase))) } },
                ecs.component.Tex{ .texture_hash = AssetManager.pathHash("assets/kattis_testcases.png"), },
            });
        }
    }
}

pub fn update(sim: *simulation.Simulation, inputs: *const input.InputState, _: Invariables) !void {

    // Game over
    if (tle) {}

    inputSystem(&sim.world, inputs);
    resetPlayersSystem(&sim.world);
    updateTestcasesTex(&sim.world);
    animator.update(&sim.world);
}

fn inputSystem(world: *ecs.world.World, inputs: *const input.InputState) void {
    if (tle) return;

    var query = world.query(&.{ ecs.component.Plr }, &.{});
    
    while (query.next()) |_| {
        const plr = query.get(ecs.component.Plr) catch unreachable;
        const state = inputs[plr.id];

        if (!state.is_connected or !waiting[plr.id]) continue;

        var pressed_a: bool = undefined;

        if (state.button_a.pressed()) { pressed_a = true; }
        else if (state.button_b.pressed()) { pressed_a = false; }
        else { continue; }

        if (correct_tcs[plr.id].isSet(current_score[plr.id]) == pressed_a) {
            completed_tcs[plr.id].setValue(current_score[plr.id], true);
            current_score[plr.id] += @as(u8, 1);
            best_score[plr.id] = @max(best_score[plr.id], current_score[plr.id]);
        }
        else { waiting[plr.id] = false; }
    }

    for (0..constants.max_player_count) |id| {
        if (completed_tcs[id].isSet(test_cases_count - 1)) { tle = true; }
    }
}

fn updateTestcasesTex(world: *ecs.world.World) void {
    var query = world.query(&.{
        ecs.component.Tex,
        ecs.component.Pos
    }, &.{ 
        ecs.component.Plr 
    });

    while (query.next()) |_| {
        const tex = query.get(ecs.component.Tex) catch unreachable;
        const pos = query.get(ecs.component.Pos) catch unreachable;

        const player_id = @as(u32, @intCast(pos.pos[0] - 4 * 16)) / (3 * 16);
        const testcase = 15 - @as(u32, @intCast(pos.pos[1])) / 16;

        if (completed_tcs[player_id].isSet(testcase)) { tex.u = 1; }
        else if (!waiting[player_id] and testcase == current_score[player_id]) { tex.u = 2; }
        else { tex.u = 0; }
    }
}

fn resetPlayersSystem(world: *ecs.world.World) void {
    var query = world.query(&.{ ecs.component.Ctr },&.{});

    while (query.next()) |_| {
        const ctr = query.get(ecs.component.Ctr) catch unreachable;

        if (waiting[ctr.id]) continue;

        if (ctr.counter == 40) {
            const range = std.bit_set.Range{ .start = 0, .end = test_cases_count };
            completed_tcs[ctr.id].setRangeValue(range, false);
            current_score[ctr.id] = @as(u8, 0);
            ctr.counter = 0;
            waiting[ctr.id] = true;
        }
        else { ctr.counter += 1; }
    }
}
