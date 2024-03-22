const std = @import("std");

pub const Identifier = u32;
pub const Generation = u32;
pub const Signature = std.bit_set.IntegerBitSet(32);

pub const Entity = packed struct {
    identifier: Identifier = 0,
    generation: Generation = 0,
};

pub const max_entities = std.math.maxInt(Identifier);
pub const max_components = Signature.bit_length;

/// A stack allocated container, storing entities and their associated
/// components. Components should preferably be zero initializable because
/// certain method depend on it.
pub fn World(comptime Cs: []const type, comptime N: usize) type {
    comptime {
        if (N > max_entities) {
            @compileError("Max entity count exceeded");
        }

        var buf_len = 0;
        for (Cs, 0..) |C, i| {
            if (i > max_components) {
                @compileError("Max component count exceeded");
            }

            buf_len += N * @sizeOf(C) + @alignOf(C);
        }

        var c_sizes: [Cs.len]usize = undefined;
        var c_alignments: [Cs.len]usize = undefined;

        for (Cs, 0..) |C, i| {
            c_sizes[i] = @sizeOf(C);
            c_alignments[i] = @alignOf(C);
        }

        return struct {
            const Self = @This();
            const Entities = std.bit_set.ArrayBitSet(u32, N);

            entities: Entities = Entities.initEmpty(),
            generations: [N]Generation = [_]Generation{0} ** N,
            signatures: [N]Signature = [_]Signature{Signature.initEmpty()} ** N,

            buf: [buf_len]u8,
            components: [Cs.len]*anyopaque,

            /// Initializes a world.
            pub fn init() Self {
                var buf: [buf_len]u8 = undefined;

                var arrays: [Cs.len]*anyopaque = undefined;
                var begin: usize = 0;
                for (0..Cs.len) |i| {
                    const c_size = c_sizes[i];
                    const c_alignment = c_alignments[i];

                    const remainder = @intFromPtr(buf[begin..].ptr) % c_alignment;
                    if (remainder != 0) begin += c_alignment - remainder;

                    const end = begin + N * c_size;
                    arrays[i] = @ptrCast(@alignCast(buf[begin..end]));

                    begin = end;
                }

                return Self{
                    .buf = buf,
                    .components = arrays,
                };
            }

            /// Creates a new entity with default initialized components.
            pub fn spawn(self: *Self, comptime c_list: []const type) Entity {
                var iter = self.entities.iterator(.{ .kind = .unset });
                const id = while (iter.next()) |i| {
                    break i;
                } else {
                    @panic("Max entity count exceeded"); // TODO: Should return error (maybe)
                };

                const entity = Entity{
                    .identifier = @intCast(id),
                    .generation = self.generations[id],
                };

                self.entities.set(id);
                self.signatures[id] = comptime componentSignature(c_list);

                inline for (c_list) |c| {
                    self.componentArray(c)[id] = .{};
                }

                return entity;
            }

            /// TODO
            /// Creates a new entity with components initialized with runtime passed values.
            pub fn spawnInit(self: *Self, c_list: anytype) !Entity {
                _ = self;
                _ = c_list;
                return .{};
            }

            /// Destroys an entity.
            pub fn kill(self: *Self, entity: Entity) void {
                std.debug.assert(self.entities.isSet(entity.identifier));

                self.entities.unset(entity.identifier);
                self.generations[entity.identifier] +%= 1;
                self.signatures[entity.identifier].mask = 0;
            }

            /// Adds default initializable components to an existing entity.
            pub fn promote(self: *Self, entity: Entity, comptime c_list: []const type) void {
                std.debug.assert(self.entities.isSet(entity.identifier));
                std.debug.assert(self.signatures[entity.identifier].intersectWith(comptime componentSignature(c_list)).mask == 0);

                inline for (c_list) |c| {
                    self.componentArray(c)[entity.identifier] = .{};
                }

                self.signatures[entity.identifier].setUnion(comptime componentSignature(c_list));
            }

            /// TODO
            /// Adds components initialized with runtime passed values to an existing entity.
            pub fn promoteInit(self: *Self, entity: Entity, c_list: anytype) void {
                _ = self;
                _ = entity;
                _ = c_list;
            }

            /// Removes components from an existing entity.
            pub fn demote(self: *Self, entity: Entity, comptime c_list: []const type) void {
                std.debug.assert(self.entities.isSet(entity.identifier));

                self.signatures[entity.identifier].setIntersection(comptime componentSignature(c_list).complement());
            }

            /// TODO
            pub fn inspect(self: *Self, entity: Entity) void {
                std.debug.assert(self.entities.isSet(entity.identifier));
            }

            /// TODO
            pub fn query(self: *Self, comptime include: []const type, comptime exclude: []const type) void {
                _ = self;
                _ = include;
                _ = exclude;
            }

            fn componentArray(self: *Self, comptime C: type) *[N]C {
                const index = comptime componentIndex(C);
                const array = self.components[index];

                return @ptrCast(@alignCast(array));
            }

            // Helpers

            fn componentSignature(comptime c_list: []const type) Signature {
                comptime {
                    var mask = Signature.initEmpty();
                    for (c_list) |c| {
                        mask.setUnion(componentTag(c));
                    }
                    return mask;
                }
            }

            fn componentTag(comptime C: type) Signature {
                comptime {
                    for (Cs, 0..) |c, i| {
                        if (c == C) {
                            var mask = Signature.initEmpty();
                            mask.set(i);
                            return mask; // 1 << i;
                        }
                    }
                    @compileError("Invalid component: " ++ @typeName(C));
                }
            }

            fn componentIndex(comptime C: type) usize {
                comptime {
                    for (Cs, 0..) |c, i| {
                        if (c == C) {
                            return i;
                        }
                    }
                    @compileError("Invalid component: " ++ @typeName(C));
                }
            }

            pub const Query = struct {
                index: usize,
                mask: Signature,

                // TODO next()
            };
        };
    }
}

// TESTS

const Pos = struct {
    x: i32 = 0,
    y: i32 = 0,
};

const Mov = struct {
    px: f32 = 0.0,
    py: f32 = 0.0,
    vx: f32 = 0.0,
    vy: f32 = 0.0,
    ax: f32 = 0.0,
    ay: f32 = 0.0,
};

const Txt = struct {
    str: ?[]const u8 = null,
    w: usize = 0,
    h: usize = 0,
};

test "init" {
    std.log.warn("begin...", .{});
    var world = World(&.{ Pos, Mov, Txt }, 2).init();

    for (world.componentArray(Pos)) |*pos| {
        std.log.warn("{*}", .{pos});
        pos.* = Pos{ .x = 0, .y = 0 };
    }

    for (world.componentArray(Mov)) |*mov| {
        std.log.warn("{*}", .{mov});
        mov.* = Mov{ .px = 0.0, .py = 0.0, .vx = 0.0, .vy = 0.0, .ax = 0.0, .ay = 0.0 };
    }

    for (world.componentArray(Txt)) |*txt| {
        std.log.warn("{*}", .{txt});
        txt.* = Txt{ .str = "", .w = 0, .h = 0 };
    }

    const player = world.spawn(&.{ Pos, Mov });
    std.log.warn("{}", .{player});

    const enemy = world.spawn(&.{ Pos, Mov });
    std.log.warn("{}", .{enemy});

    world.kill(enemy);

    const text = world.spawn(&.{Txt});
    world.promote(text, &.{Pos});
    std.log.warn("{}", .{text});

    world.query(&.{Pos}, &.{Mov});
}

// fn typeName(comptime T: type) [:0]const u8 {
//     comptime {
//         var name = @typeName(T).*;
//         for (name, 0..) |c, i| {
//             if (c == '.') name[i] = '_';
//         }
//         return &name;
//     }
// }
