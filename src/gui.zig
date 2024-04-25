const Simulation = @import("simulation.zig").Simulation;
const ecs = @import("ecs/ecs.zig");

/// Displays a crown over the player with the highest score.
pub fn crownSystem(sim: *Simulation) void {
    _ = sim;
}

/// Displays an identifying symbol over each player.
pub fn playerSystem(world: *ecs.world.World) void {
    _ = world;
}
