const std = @import("std");
const cps = @import("components.zig");
const sys = @import("systems.zig");

/// This constant determines the maximum number of entities a World supports.
pub const N: usize = 10;

/// This constant determines which components a World supports.
pub const Cs: []const type = &.{
    cps.Pos,
    cps.Vel,
};

pub const Identifier = u32;
pub const Generation = u32;
pub const Signature = std.bit_set.IntegerBitSet(Cs.len);

pub const Entity = packed struct {
    identifier: Identifier = 0,
    generation: Generation = 0,
};

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
};

pub const World = struct {
    const Self = @This();
    const Entities = std.bit_set.ArrayBitSet(u32, N);
    comptime VALID_COMPONENTS: void = for (Cs) |C| {
        if (@typeInfo(C) != .Struct) @compileError("Components must be structs");
    },

    entities: Entities = Entities.initEmpty(),
    generations: [N]Generation = [_]Generation{0} ** N,
    signatures: [N]Signature = [_]Signature{Signature.initEmpty()} ** N,
    buffer: [buffer_size]u8,
    components: [Cs.len]*anyopaque,

    pub fn init() Self {
        var buffer: [buffer_size]u8 = undefined;
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

    pub fn kill(self: *Self, entity: Entity) void {
        std.debug.assert(self.entities.isSet(entity.identifier));

        self.entities.unset(entity.identifier);
        self.generations[entity.identifier] +%= 1;
        self.signatures[entity.identifier].mask = 0;
    }

    pub fn promote(self: *Self, entity: Entity, comptime Components: []const type) void {
        std.debug.assert(self.entities.isSet(entity.identifier));
        std.debug.assert(self.signatures[entity.identifier].intersectWith(comptime componentSignature(Components)).mask == 0);

        inline for (Components) |C| {
            self.componentArray(C)[entity.identifier] = .{};
        }

        self.signatures[entity.identifier].setUnion(comptime componentSignature(Components));
    }

    pub fn demote(self: *Self, entity: Entity, comptime Components: []const type) void {
        std.debug.assert(self.entities.isSet(entity.identifier));
        std.debug.assert(self.signatures[entity.identifier].complement().intersectWith(comptime componentSignature(Components)).mask == 0);

        self.signatures[entity.identifier].setIntersection(comptime componentSignature(Components).complement());
    }

    fn componentArray(self: *Self, comptime Component: type) *[N]Component {
        const index = comptime componentIndex(Component);
        const component = self.components[index];

        return @ptrCast(@alignCast(component));
    }

    pub fn query(self: *Self, comptime Include: []const type, comptime Exclude: []const type) Query(Include, Exclude) {
        return Query(Include, Exclude).init(self);
    }

    fn Query(comptime Include: []const type, comptime Exclude: []const type) type {
        return struct {
            world: *World,
            cursor: ?usize = null,
            iterator: Entities.Iterator(.{}),

            pub fn init(world: *World) @This() {
                return @This(){ .world = world, .iterator = world.entities.iterator(.{}) };
            }

            pub fn next(self: *@This()) ?Entity {
                const include = comptime componentSignature(Include);
                const exclude = comptime componentSignature(Exclude);

                while (self.iterator.next()) |i| {
                    const signature = self.world.signatures[i];
                    if (signature.intersectWith(include).intersectWith(exclude.complement()).mask == 0) {
                        self.cursor = i;
                        return Entity{ .identifier = @intCast(i), .generation = self.world.generations[i] };
                    }
                }

                return null;
            }

            pub fn get(self: *@This(), comptime C: type) !*C {
                if (self.cursor) |i| {
                    const index = comptime for (Include, 0..) |c, j| {
                        if (c == C) {
                            break j;
                        }
                    } else {
                        @compileError("Invalid component: " ++ @typeName(C));
                    };

                    const array: *[N]C = @ptrCast(@alignCast(self.world.components[index]));

                    return &array[i];
                }
                return WorldError.NullQuery;
            }
        };
    }
};

fn componentIndex(comptime Component: type) usize {
    comptime {
        for (Cs, 0..) |c, i| {
            if (c == Component) {
                return i;
            }
        }
        @compileError("Invalid component: " ++ @typeName(Component));
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

test "spawn_promote_demote_kill" {
    var world = World.init();

    const entity = try world.spawn(&.{cps.Pos});

    try std.testing.expect(entity.identifier == 0 and entity.generation == 0);

    world.promote(entity, &.{cps.Vel});
    world.demote(entity, &.{cps.Vel});
    world.kill(entity);
}

test "spawn_limit" {
    var world = World.init();

    for (0..N) |_| {
        _ = try world.spawn(&.{});
    }

    try std.testing.expect(world.spawn(&.{}) == WorldError.SpawnLimitExceeded);
}

test "run_system" {
    var world = World.init();

    for (0..N) |_| {
        _ = try world.spawn(&.{ cps.Pos, cps.Vel });
    }

    try system(&world);
}

pub fn system(world: *World) !void {
    var query = world.query(&.{ cps.Pos, cps.Vel }, &.{});
    while (query.next()) |_| {
        const pos = try query.get(cps.Pos);
        const vel = try query.get(cps.Vel);

        pos.x += std.math.lossyCast(i32, vel.x);
        pos.y += std.math.lossyCast(i32, vel.y);
    }
}

// const ecs = @import("ecs.zig");

// const Pos = struct { i32, i32 };
// const Vel = struct { i32, i32 };

// const WorldType = ecs.World(&.{ Pos, Vel });

// pub fn move(world: *WorldType) void {
//     var query = world.query(&.{ Pos, Vel });

//     while (query.next()) |entity| {
//         const pos = query.get(Pos);
//         const vel = query.get(Vel);

//         pos.x += vel.x;
//         pos.y += vel.y;
//     }
// }

// pub fn main() void {
//     var world = WorldType.init();

//     while (true) {
//         move(&world);
//     }
// }
