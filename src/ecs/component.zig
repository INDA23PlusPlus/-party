const rl = @import("raylib");

const F32 = @import("../math/fixed.zig").F(16, 16);
const Vec2 = @import("../math/linear.zig").V(2, F32);

/// Components the ECS supports.
/// All components MUST be default initializable.
/// All components MUST have a documented purpose.
pub const components: []const type = &.{
    Pos,
    Mov,
    Col,
    Tex,
    Txt,
    Ctl,
};

/// Entities with this component are positionable.
pub const Pos = struct {
    vec: @Vector(2, i32) = .{ 0, 0 },
};

/// Entities with this component are movable.
pub const Mov = struct {
    subpixel: Vec2 = Vec2{},
    velocity: Vec2 = Vec2{},
    acceleration: Vec2 = Vec2{},
};

/// Entities with this component are collidable.
pub const Col = struct {
    w: i32 = 0,
    h: i32 = 0,
    layer: enum { FG, BG } = .FG,
};

/// Entities with this component have associated text.
pub const Txt = struct {
    string: []const u8 = "", // TODO: use hash instead of slice
};

/// Entities with this component have an associated texture.
pub const Tex = struct {
    texture_hash: u64 = 0, // TODO: add default texture to renderer?
    tint: rl.Color = rl.Color.white, // TODO: does this work for serialization?
    scale: F32 = F32.fromInt(1),
    rotate: enum { R0, R90, R180, R270 } = .R0,
    mirror: bool = false,
    u: usize = 0,
    v: usize = 0,
};

/// Entities with this component are associated with a controller.
pub const Ctl = struct {
    id: usize,
};
