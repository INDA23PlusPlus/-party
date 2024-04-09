comptime {
    _ = @import("ecs/test.zig");
    _ = @import("math/fixed.zig");
    _ = @import("math/linear.zig");
}

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
