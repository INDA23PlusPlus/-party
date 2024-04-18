const rl = @import("raylib");

const Layer = @import("../physics/collision.zig").Layer;

const Entity = @import("entity.zig").Entity;
const entity_count = @import("world.zig").N;

pub const F32 = @import("../math/fixed.zig").F(16, 16);
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
    Lnk,
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

/// Entities with this component are collidable.
pub const Col = struct {
    dim: @Vector(2, i32) = .{ 0, 0 }, // w, h
    layer: Layer = Layer{}, // Determines what entities collide with this entity.
    mask: Layer = Layer{}, // Determines what entities this entity collides with.
};

/// Entities with this component may be linked to other entities.
pub const Lnk = struct {
    child: ?Entity = null,
};

/// Entities with component point in a direction.
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
    string: [:0]const u8 = "", // TODO: use hash instead of slice
    color: u32 = 0xFFFFFFFF,
    font_size: u8 = 24,
    draw: bool = true, // This is very ugly, but is useful for menu items. Change if needed. (Use dynamic strings??)
};

/// Entities with this component have an associated texture.
pub const Tex = struct {
    u: usize = 0,
    v: usize = 0,
    tiles_x: u16 = 1,
    tiles_y: u16 = 1,
    texture_hash: u64 = 0, // TODO: add default texture to renderer?
    tint: rl.Color = rl.Color.white, // TODO: does this work for serialization?
    scale: F32 = F32.fromInt(1),
    rotate: enum { R0, R90, R180, R270 } = .R0,
    mirror: bool = false,
};

/// Entities with this component are animated.
pub const Anm = struct {
    animation: Animation = Animation.KattisIdle,
    subframe: usize = 0,
    interval: usize = 1,
    looping: bool = true,
};
