comptime {
    _ = @import("ecs/ecs.zig");
    _ = @import("math/fixed.zig");
    _ = @import("math/linear.zig");
}

test {
    @import("std").testing.refAllDecls(@This());
}
