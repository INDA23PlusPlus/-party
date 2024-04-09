const std = @import("std");
const fixed = @import("../math/fixed.zig");
const linear = @import("../math/linear.zig");
const cps = @import("component.zig");
const ent = @import("entity.zig");

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
//  - [X] Use indices instead of pointers into the buffer, and move the initialization of the buffer into World.

// WORLD

/// Determines the maximum number of entities a World supports.
pub const N: usize = 128;
pub const Cs = cps.components;

pub const Entities = std.bit_set.ArrayBitSet(u64, N);
pub const Signature = std.bit_set.IntegerBitSet(Cs.len);

const Entity = ent.Entity;
const Identifier = ent.Identifier;
const Generation = ent.Generation;

// TODO: fit all data exactly.
const buffer_size = blk: {
    var size = 0;
    for (Cs) |C| {
        size += N * @sizeOf(C) + @alignOf(C);
    }
    break :blk size;
};

const buffer_alignment = if (Cs.len > 0) @alignOf(Cs[0]) else 0;

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

// Maps component identifiers to their corresponding buffer index.
const component_handles = blk: {
    var components: [Cs.len]usize = undefined;
    var cursor: usize = 0;

    for (0..Cs.len) |i| {
        const size = component_sizes[i];
        const alignment = component_alignments[i];
        const remainder = cursor % alignment;

        if (remainder != 0) cursor += alignment - remainder;

        components[i] = cursor;
        cursor = cursor + N * size;
    }

    break :blk components;
};

pub const WorldError = error{
    SpawnLimitExceeded,
    NullQuery,
    DeadInspection,
    InvalidInspection,
};

/// Stores and manipulates entities and their corresponding components.
pub const World = struct {
    const Self = @This();

    comptime VALID_COMPONENTS: void = for (Cs) |C| {
        if (@typeInfo(C) != .Struct) @compileError("components must be structs");
    },

    entities: Entities = Entities.initEmpty(),
    generations: [N]Generation = [_]Generation{0} ** N,
    signatures: [N]Signature = [_]Signature{Signature.initEmpty()} ** N,
    buffer: [buffer_size]u8 align(buffer_alignment) = undefined,

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
        const identifier = comptime componentIdentifier(Component);
        const handle = comptime component_handles[identifier];
        const ptr: *anyopaque = self.buffer[handle..];

        return @ptrCast(@alignCast(ptr));
    }
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

            comptime for (Include) |c| {
                if (c == C) break;
            } else {
                @compileError("invalid component: " ++ @typeName(C));
            };

            return &self.world.componentArray(C)[cursor];
        }
    };
}

// HELPERS

fn componentIdentifier(comptime Component: type) usize {
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
