const std = @import("std");
const fixed = @import("../math/fixed.zig");
const linear = @import("../math/linear.zig");

// TODO:
//  - [X] Implement isAlive()
//  - [ ] Implement hasComponents()
//  - [ ] Implement setComponents()
//  - [ ] Implement respawn()
//  - [ ] Implement respawnWith()
//  - [ ] Implement respawnEmpty()
//  - [ ] Implement promoteWith()
//  - [ ] Implement promoteEmpty()
//  - [ ] Implement spawnEmpty()
//  - [ ] Implement serialize()
//  - [ ] Implement deserialize()
//  - [ ] Implement replace() (kill() then spawn(), faster)
//  - [ ] Implement replaceWith() (kill() then spawnWith(), faster)
//  - [ ] Use indices instead of pointers into the buffer, and move initialization of the buffer into World.

// COMPONENTS

pub const Position = struct {
    x: i32 = 0,
    y: i32 = 0,
};

const F32 = fixed.F(16, 16);
const V2 = linear.V(2, F32);

pub const Mover = struct {
    subpixel: V2 = V2{},
    velocity: V2 = V2{},
    acceleration: V2 = V2{},
};

pub const Collider = struct {
    w: i32 = 0,
    h: i32 = 0,
    collided: ?[]Entity = null,
};

// pub const Texture = struct {
//     file: []const u8 = "",
//     texture: ?*anyopaque = null,
//     src_x: i32 = 0,
//     src_y: i32 = 0,
//     src_w: i32 = 0,
//     src_h: i32 = 0,
//     dst_x: i32 = 0, // Useful for positioning a texture more accurately
//     dst_y: i32 = 0, // Useful for positioning a texture more accurately
//     dst_w: i32 = 0,
//     dst_h: i32 = 0,
// };

pub const Text = struct {
    string: []const u8 = "",
};

// WORLD

/// Determines the maximum number of entities a World supports.
pub const N: usize = 512;

const TextureComponent = @import("../render.zig").TextureComponent;

/// Determines which components a World supports.
pub const Cs: []const type = &.{
    Position,
    Mover,
    Collider,
    TextureComponent,
    Text,
};

pub const Identifier = u32;
pub const Generation = u32;
pub const Signature = std.bit_set.IntegerBitSet(Cs.len);

pub const Entity = packed struct {
    const Self = @This();
    const Bits = @typeInfo(Self).Struct.backing_integer.?;

    identifier: Identifier = 0,
    generation: Generation = 0,

    pub inline fn toBits(self: Self) Bits {
        return @bitCast(self);
    }

    pub inline fn fromBits(bits: Bits) Self {
        return @bitCast(bits);
    }

    pub inline fn eq(a: Self, b: Self) bool {
        return a.toBits() == b.toBits();
    }

    pub inline fn ne(a: Self, b: Self) bool {
        return a.toBits() != b.toBits();
    }
};

const Entities = std.bit_set.ArrayBitSet(u64, N);

const buffer_size = blk: {
    var size = 0;
    for (Cs) |C| {
        size += N * @sizeOf(C) + @alignOf(C);
    }
    break :blk size;
};

const component_sizes = blk: {
    var sizes: [Cs.len]usize = undefined;
    for (Cs, 0..) |C, i| {
        sizes[i] = @sizeOf(C);
    }
    break :blk sizes;
};

const component_alignments = blk: {
    var alignments: [Cs.len]usize = undefined;
    for (Cs, 0..) |C, i| {
        alignments[i] = @alignOf(C);
    }
    break :blk alignments;
};

pub const WorldError = error{
    SpawnLimitExceeded,
    NullQuery,
    DeadInspection,
    InvalidInspection,
};

// This can be moved into World.init() when Zig gets pinned structs.
pub const Buffer = [buffer_size]u8;

/// Stores and manipulates entities and their corresponding components.
pub const World = struct {
    const Self = @This();

    comptime VALID_COMPONENTS: void = for (Cs) |C| {
        if (@typeInfo(C) != .Struct) @compileError("components must be structs");
    },

    entities: Entities = Entities.initEmpty(),
    generations: [N]Generation = [_]Generation{0} ** N,
    signatures: [N]Signature = [_]Signature{Signature.initEmpty()} ** N,
    buffer: *[buffer_size]u8,
    components: [Cs.len]*anyopaque,

    /// Creates a new world.
    pub fn init(buffer: *Buffer) Self {
        var components: [Cs.len]*anyopaque = undefined;
        var cursor: usize = 0;
        for (0..Cs.len) |i| {
            const size = component_sizes[i];
            const alignment = component_alignments[i];

            const remainder = @intFromPtr(buffer[cursor..].ptr) % alignment;
            if (remainder != 0) cursor += alignment - remainder;

            components[i] = @ptrCast(@alignCast(buffer[cursor..]));

            cursor = cursor + N * size;
        }

        return Self{
            .buffer = buffer,
            .components = components,
        };
    }

    /// Removes all entities from the world.
    pub fn reset(self: *Self) void {
        self.entities = Entities.initEmpty();
        self.generations = [_]Generation{0} ** N;
        self.signatures = [_]Signature{Signature.initEmpty()} ** N;
    }

    /// Creates a new entity with default intialized components.
    pub fn spawn(self: *Self, comptime Components: []const type) !Entity {
        const identifier = self.entities.complement().findFirstSet() orelse return WorldError.SpawnLimitExceeded;

        const entity = Entity{
            .identifier = @intCast(identifier),
            .generation = self.generations[identifier],
        };

        self.entities.set(identifier);
        self.signatures[identifier] = comptime componentSignature(Components);

        inline for (Components) |C| {
            self.componentArray(C)[identifier] = .{};
        }

        return entity;
    }

    /// Creates a new entity with components inferred from passed values.
    pub fn spawnWith(self: *Self, Components: anytype) !Entity {
        const identifier = self.entities.complement().findFirstSet() orelse return WorldError.SpawnLimitExceeded;

        const Type = @TypeOf(Components);
        const info = @typeInfo(Type);
        if (info != .Struct) {
            @compileError("expected tuple or struct argument, found " ++ @typeName(Type));
        }

        const entity = Entity{
            .identifier = @intCast(identifier),
            .generation = self.generations[identifier],
        };

        self.entities.set(identifier);

        const fields = info.Struct.fields;
        inline for (fields) |field| {
            const component = @field(Components, field.name);
            self.componentArray(@TypeOf(component))[identifier] = component;
            self.signatures[identifier].setUnion(comptime componentTag(@TypeOf(component)));
        }

        return entity;
    }

    /// Removes an entity.
    pub fn kill(self: *Self, entity: Entity) void {
        std.debug.assert(self.entities.isSet(entity.identifier));

        self.entities.unset(entity.identifier);
        self.generations[entity.identifier] +%= 1;
        self.signatures[entity.identifier].mask = 0;
    }

    /// Adds default initialized components to an entity.
    pub fn promote(self: *Self, entity: Entity, comptime Components: []const type) void {
        std.debug.assert(self.entities.isSet(entity.identifier));
        std.debug.assert(self.signatures[entity.identifier].intersectWith(comptime componentSignature(Components)).mask == 0);

        inline for (Components) |C| {
            self.componentArray(C)[entity.identifier] = .{};
        }

        self.signatures[entity.identifier].setUnion(comptime componentSignature(Components));
    }

    /// TODO
    /// Adds components to an entity. Components should be passed as a struct.
    pub fn promoteWith(self: *Self, entity: Entity, Components: anytype) void {
        _ = self;
        _ = entity;
        _ = Components;
    }

    /// TODO
    /// Removes all components and then readds default initialized components to an entity.
    pub fn respawn(self: *Self, entity: Entity, comptime Components: []const type) !void {
        _ = self;
        _ = entity;
        _ = Components;
    }

    /// TODO
    /// Removes all components and then readds components passed as a struct to an entity.
    pub fn respawnWith(self: *Self, entity: Entity, Components: anytype) !void {
        _ = self;
        _ = entity;
        _ = Components;
    }

    /// TODO
    /// Creates a new entity without any components.
    pub fn spawnEmpty(self: *Self) !Entity {
        _ = self;
    }

    /// TODO
    /// Removes all components from an entity.
    pub fn respawnEmpty(self: *Self, entity: Entity) !void {
        _ = self;
        _ = entity;
    }

    /// Removes components from an entity.
    pub fn demote(self: *Self, entity: Entity, comptime Components: []const type) void {
        std.debug.assert(self.entities.isSet(entity.identifier));
        std.debug.assert(self.signatures[entity.identifier].complement().intersectWith(comptime componentSignature(Components)).mask == 0);

        self.signatures[entity.identifier].setIntersection(comptime componentSignature(Components).complement());
    }

    pub fn isAlive(self: *Self, entity: Entity) bool {
        if (!self.entities.isSet(entity.identifier)) {
            return false;
        }

        return entity.generation == self.generations[entity.identifier];
    }

    /// Retrieves a component from an entity. Prefer using query().
    pub fn inspect(self: *Self, entity: Entity, comptime C: type) !*C {
        if (!isAlive(self, entity)) return WorldError.DeadInspection;

        if (self.signatures[entity.identifier].intersectWith(comptime componentTag(C)).mask == 0) {
            return WorldError.InvalidInspection;
        }

        return &self.componentArray(C)[entity.identifier];
    }

    /// Constructs a Query.
    pub fn query(self: *Self, comptime Include: []const type, comptime Exclude: []const type) Query(Include, Exclude) {
        return Query(Include, Exclude).init(self);
    }

    fn componentArray(self: *Self, comptime Component: type) *[N]Component {
        const index = comptime componentIndex(Component);
        const component = self.components[index];

        return @ptrCast(@alignCast(component));
    }
};

/// A world paired together with an rw_lock used
/// to coordinate two (or more) threads accessing the same world.
/// OBS: This does not automatically make procedures inside
/// of World thread-safe. The rw_lock must be properly used first.
pub const SharedWorld = struct {
    rw_lock: std.Thread.RwLock,
    world: World,
};

// QUERY

/// An iterator over entites with a specific set of components.
/// Included components refers to components that the entity must have.
/// Excluded components refers to components that the entity must not have.
fn Query(comptime Include: []const type, comptime Exclude: []const type) type {
    comptime {
        for (Include) |I| {
            for (Exclude) |E| {
                if (I == E) {
                    @compileError("query both includes and excludes " ++ @typeName(I));
                }
            }
        }
    }

    return struct {
        world: *World,
        cursor: ?usize = null,
        iterator: Entities.Iterator(.{}),

        pub fn init(world: *World) @This() {
            return @This(){ .world = world, .iterator = world.entities.iterator(.{}) };
        }

        /// Queries the next entity.
        pub fn next(self: *@This()) ?Entity {
            const include = comptime componentSignature(Include);
            const exclude = comptime componentSignature(Exclude);

            while (self.iterator.next()) |i| {
                const signature = self.world.signatures[i];
                if (signature.intersectWith(include).differenceWith(exclude).mask != 0) {
                    self.cursor = i;
                    return Entity{ .identifier = @intCast(i), .generation = self.world.generations[i] };
                }
            }

            return null;
        }

        /// Retrieves a component for the current queried entity.
        pub fn get(self: *@This(), comptime C: type) !*C {
            const cursor = self.cursor orelse return WorldError.NullQuery;

            const index = comptime for (Include) |c| {
                if (c == C) {
                    break componentIndex(c);
                }
            } else {
                @compileError("invalid component: " ++ @typeName(C));
            };

            const array: *[N]C = @ptrCast(@alignCast(self.world.components[index]));

            return &array[cursor];
        }
    };
}

// HELPERS

fn componentIndex(comptime Component: type) usize {
    comptime {
        for (Cs, 0..) |c, i| {
            if (c == Component) {
                return i;
            }
        }
        @compileError("invalid component: " ++ @typeName(Component));
    }
}

fn componentTag(comptime Component: type) Signature {
    comptime {
        for (Cs, 0..) |c, i| {
            if (c == Component) {
                var mask = Signature.initEmpty();
                mask.set(i);
                return mask;
            }
        }
        @compileError("Invalid component: " ++ @typeName(Component));
    }
}

fn componentSignature(comptime Components: []const type) Signature {
    comptime {
        var mask = Signature.initEmpty();
        for (Components) |c| {
            mask.setUnion(componentTag(c));
        }
        return mask;
    }
}

// TESTS

test "spawn_promote_demote_kill" {
    var buffer: Buffer = undefined;
    var world = World.init(&buffer);

    const entity = try world.spawn(&.{Position});

    try std.testing.expect(entity.identifier == 0 and entity.generation == 0);

    world.promote(entity, &.{Mover});
    world.demote(entity, &.{Mover});
    world.kill(entity);
}

test "spawn_limit" {
    var buffer: Buffer = undefined;
    var world = World.init(&buffer);

    for (0..N) |_| {
        _ = try world.spawn(&.{});
    }

    try std.testing.expect(world.spawn(&.{}) == WorldError.SpawnLimitExceeded);
}

test "reset" {
    var buffer: Buffer = undefined;
    var world = World.init(&buffer);

    for (0..N) |_| {
        _ = try world.spawn(&.{ Position, Mover });
    }

    var query1 = world.query(&.{Position}, &.{});
    while (query1.next()) |_| {
        const pos = try query1.get(Position);
        if (!(pos.x == 0 and pos.y == 0)) {
            unreachable;
        }
    }

    // try accelerate(&world);
    // try move(&world);

    world.reset();

    for (0..N / 2) |_| {
        _ = try world.spawn(&.{ Position, Mover });
    }

    var query2 = world.query(&.{Position}, &.{});
    while (query2.next()) |_| {
        const pos = try query2.get(Position);
        if (!(pos.x == 0 and pos.y == 0)) {
            unreachable;
        }
    }

    // try accelerate(&world);
    // try move(&world);
}

test "build entities" {
    var buffer: Buffer = undefined;
    var world = World.init(&buffer);

    for (0..N) |i| {
        const j: i32 = @intCast(i);
        const col = Collider{};
        const pos = Position{ .x = j, .y = j };
        _ = try world.spawnWith(.{ pos, col });
    }
}
