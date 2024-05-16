const rl = @import("raylib");

const constants = @import("../constants.zig");

const Layer = @import("../physics/collision.zig").Layer;

const Entity = @import("entity.zig").Entity;
const World = @import("world.zig").World;

const entity_count = @import("world.zig").N;

pub const F32 = @import("../math/fixed.zig").F(16, 16);
pub const Vec2 = @import("../math/linear.zig").V(2, F32);
const Animation = @import("../animation/animations.zig").Animation;
const AssetManager = @import("../AssetManager.zig");
const AudioManager = @import("../AudioManager.zig");

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
    Anm,
    Lnk,
    Ctr,
    Tmr,
    Snd,
    // Tags
    Dbg,
    Air,
    Jmp,
    Atk,
    Hit,
    Blk,
    Kng,
    Src,
    Txt,
    Str,
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

/// Entities with component can point in a direction.
pub const Dir = struct {
    facing: enum {
        None,
        North,
        South,
        West,
        East,
        Northwest,
        Northeast,
        Southwest,
        Southeast,
    } = .None,
};

/// Entities with this component are player controllable.
pub const Plr = struct {
    id: u32 = 0, // Use this value to find the correct player input.
};

/// Entities with this component render text using a asset hash just like Tex components. All strings must be added to the list in AssetManager at comptime
pub const Txt = struct {
    hash: u64 = AssetManager.default_string_hash,
    color: u32 = 0xFFFFFFFF,
    font_size: u8 = 1,
    subpos: @Vector(2, i32) = .{ 0, 0 },
};

/// Entities with this component have an associated texture.
pub const Tex = struct {
    texture_hash: u64 = AssetManager.default_hash,
    u: u32 = 0,
    v: u32 = 0,
    w: u32 = 1,
    h: u32 = 1,
    subpos: @Vector(2, i32) = .{ 0, 0 },
    tint: rl.Color = rl.Color.white,
    rotate: enum { R0, R90, R180, R270 } = .R0,
    flip_horizontal: bool = false,
    flip_vertical: bool = false,
    size: u8 = 1, // TODO: scale texture when rendering
};

/// Entities with this component
pub const Snd = struct {
    sound_hash: u8 = AudioManager.path_to_key(AudioManager.default_audio),
};

/// Entities with this component are animated.
pub const Anm = struct {
    subframe: u32 = 0,
    interval: u32 = 1,
    animation: Animation = Animation.Default,
    looping: bool = true,
};

/// Entities with this component can count.
pub const Ctr = struct {
    count: u32 = 0,
};

/// Entities with this component can time.
pub const Tmr = struct {
    ticks: u32 = 0,
};

/// Entities with this component can exert unique behaviour for debugging purposes.
pub const Dbg = struct {};

/// Entities with this component are in an airborne state.
pub const Air = struct {};

/// Entities with this component are in a jumping state.
pub const Jmp = struct {};

/// Entities with this component are in an attacking state.
pub const Atk = struct {};

/// Entities with this component are in a hit state.
pub const Hit = struct {};

/// Entities with this component are in a blocking state.
pub const Blk = struct {};

/// The crown entity uses this tag as an identifier.
/// Could potentially be used to make the leading player behave differently.
pub const Kng = struct {};

/// Entities with this component act as the source of something.
pub const Src = struct {};

/// Entities with this component act as strings.
pub const Str = struct {};
