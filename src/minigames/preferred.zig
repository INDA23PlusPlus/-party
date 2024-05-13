/// The only purpose of this minigame is to use metadata to switch over to a preferred minigame.
/// This is done so that we do not need to call init() in two places. Do not put important stuff in this
/// minigame's init() as it is never called as a consequences. In fact, expect almost everything to not be
/// initialized properly.
const simulation = @import("../simulation.zig");
const input = @import("../input.zig");
const Invariables = @import("../Invariables.zig");

pub fn init(_: *simulation.Simulation, _: input.Timeline) !void {}

pub fn update(sim: *simulation.Simulation, _: input.Timeline, _: Invariables) !void {
    sim.meta.minigame_id = sim.meta.preferred_minigame_id;
}
