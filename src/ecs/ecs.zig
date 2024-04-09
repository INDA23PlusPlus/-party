pub const world = @import("world.zig");
pub const component = @import("component.zig");
pub const entity = @import("entity.zig");

/// A world paired together with an rw_lock used
/// to coordinate two (or more) threads accessing the same world.
/// OBS: This does not automatically make procedures inside
/// of World thread-safe. The rw_lock must be properly used first.
pub const SharedWorld = struct {
    rw_lock: @import("std").Thread.RwLock,
    world: world.World,
};
