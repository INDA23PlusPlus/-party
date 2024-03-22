const ecs = @import("ecs.zig");

// WorldType

const WorldType = ecs.World(&.{
    Player,
    Position,
    Movable,
    Collidable,
    Texture,
}, 512);

// Types

const IVec = struct {
    x: i32 = 0,
    y: i32 = 0,
};

const FVec = struct {
    x: f32 = 0,
    y: f32 = 0,
};

const Rect = struct {
    w: i32 = 0,
    h: i32 = 0,
};

// Components

const Player = struct {
    identifier: u8 = 0,
};

const Position = struct {
    position: IVec = .{},
};

const Movable = struct {
    subpixel: FVec = .{},
    velocity: FVec = .{},
    acceleration: FVec = .{},
};

const Collidable = struct {
    rectangle: Rect = .{},
    collided: []ecs.Entity = &.{},
};

const Texture = struct {
    ptr: ?*anyopaque = null,
    source_position: IVec = .{},
    source_rectangle: Rect = .{},
    destination_rectangle: Rect = .{},
};

// Systems

pub fn collide(world: *WorldType) void {
    _ = world;
}

pub fn move(world: *WorldType) void {
    _ = world;
}

test "run" {
    var world = WorldType.init();

    // Entities are identifiers returned from the spawn method
    const player = world.spawn(&.{});

    // Components can be added to entities at runtime
    world.promote(player, &.{
        Player,
        Position,
        Movable,
        Collidable,
        Texture,
    });

    // Entities can be destroyed using the corresponding identifier
    world.kill(player);

    // An entity's starting components can be passed as arguments upon creation
    const object = world.spawn(&.{
        Position,
        Collidable,
        Texture,
    });

    // Components can be removed from an entity at runtime
    world.demote(object, &.{Texture});

    // Game loop (should loop forever)
    while (true) {
        collide(&world);
        move(&world);
        break;
    }
}
