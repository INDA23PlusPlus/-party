comptime {
    _ = @import("ecs/test.zig");
    _ = @import("math/fixed.zig");
    _ = @import("math/linear.zig");
    _ = @import("physics/collision.zig");
    _ = @import("physics/movement.zig");
    _ = @import("minigames/tron.zig");
}

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
