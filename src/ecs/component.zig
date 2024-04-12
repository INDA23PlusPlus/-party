const rl = @import("raylib");

const Entity = @import("entity.zig").Entity;
const entity_count = @import("world.zig").N;

const F32 = @import("../math/fixed.zig").F(16, 16);
pub const Vec2 = @import("../math/linear.zig").V(2, F32);
const Animation = @import("../animation/animations.zig").Animation;

/// Components the ECS supports.
/// All components MUST be default initializable.
/// All components MUST have a documented purpose.
pub const components: []const type = &.{
    Plr,
    Pos,
    Mov,
    Col,
    Dir,
    Tex,
    Txt,
    Anm,
};

/// Entities with this component are positionable.
pub const Pos = struct {
    pos: @Vector(2, i32) = .{ 0, 0 }, // x, y
};

/// Entities with this component are movable.
pub const Mov = struct {
    subpixel: Vec2 = Vec2{},
    velocity: Vec2 = Vec2{},
    acceleration: Vec2 = Vec2{},
};

/// Bitmask for collisions.
pub const Layer = packed struct {
    base: bool = false,
    // Add game specific layers here.
};

/// Entities with this component are collidable.
pub const Col = struct {
    dim: @Vector(2, i32) = .{ 0, 0 }, // w, h
    layer: Layer = Layer{},
};

/// Entities with component have a direction they point too.
pub const Dir = struct {
    // Do not add a None, value to this enum.
    // If an entity does not have a facing,
    // then it should not have a Dir component.
    // Components are cheap to remove at runtime.
    facing: enum {
        North,
        South,
        West,
        East,
        Northwest,
        Northeast,
        Southwest,
        Southeast,
    } = .North,
};

/// Entities with this component are player controllable.
pub const Plr = struct {
    id: usize = 0, // Use this value to find the correct player input.
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

/// Entities with this component are animated.
pub const Anm = struct {
    animation: Animation = Animation.KattisIdle,
    subframe: usize = 0,
    interval: usize = 1,
    looping: bool = true,
};
