const rl = @import("raylib");
const std = @import("std");
const ecs = @import("ecs/ecs.zig");
const AssetManager = @import("AssetManager.zig");

pub fn encode(char: u8) u32 {
    if (char < 32) unreachable;
    return char - 32;
}

pub const signature = .{
    ecs.component.Pos,
    ecs.component.Tex,
    ecs.component.Ctr,
    ecs.component.Lnk,
    ecs.component.Src,
    ecs.component.Str,
};

pub fn spawn(
    world: *ecs.world.World,
    position: @Vector(2, i32),
    size: u8,
    tint: rl.Color,
    value: u32,
) !ecs.entity.Entity {
    if (value <= 9) {
        return world.spawnWith(.{
            ecs.component.Pos{ .pos = position },
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/monogram_bitmap.png"),
                .size = size,
                .tint = tint,
                .u = encode('0') + value,
            },
            ecs.component.Ctr{ .count = value },
            ecs.component.Lnk{},
            ecs.component.Src{},
            ecs.component.Str{},
        });
    }

    const digits_minus_one: u16 = std.math.log10_int(value);
    var child: ?ecs.entity.Entity = null;
    var digit: u16 = 0;
    var number = value;

    while (digit < digits_minus_one) : (digit += 1) {
        const pow = std.math.powi(u32, 10, digits_minus_one - digit) catch unreachable;
        const first_digit = number / pow;
        number -= first_digit * pow;

        child = try world.spawnWith(.{
            ecs.component.Pos{ .pos = position + [_]i32{ 6 * size * digit, 0 } },
            ecs.component.Tex{
                .texture_hash = AssetManager.pathHash("assets/monogram_bitmap.png"),
                .size = size,
                .tint = tint,
                .u = encode('0') + first_digit,
            },
            ecs.component.Ctr{ .count = first_digit },
            ecs.component.Lnk{ .child = child },
            ecs.component.Str{},
        });
    }

    return world.spawnWith(.{
        ecs.component.Pos{ .pos = position + [_]i32{ 6 * size * digits_minus_one, 0 } },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/monogram_bitmap.png"),
            .size = size,
            .tint = tint,
            .u = encode('0') + number,
        },
        ecs.component.Ctr{ .count = number },
        ecs.component.Lnk{ .child = child },
        ecs.component.Src{},
        ecs.component.Str{},
    });
}

pub fn increment(world: *ecs.world.World, entity: ecs.entity.Entity) !bool {
    const pos = try world.inspect(entity, ecs.component.Pos);
    const tex = try world.inspect(entity, ecs.component.Tex);
    const ctr = try world.inspect(entity, ecs.component.Ctr);
    const lnk = try world.inspect(entity, ecs.component.Lnk);

    if (world.checkSignature(entity, &.{}, &.{ecs.component.Str})) {
        return ecs.world.WorldError.InvalidInspection;
    }

    ctr.count += 1;
    tex.u += 1;

    if (ctr.count > 9) {
        ctr.count = 0;
        tex.u = encode('0');

        if (lnk.child) |child| {
            if (try increment(world, child)) {
                pos.pos += .{ 6 * tex.size, 0 };
                return true;
            }
        } else {
            lnk.child = try world.spawnWith(.{
                ecs.component.Pos{ .pos = pos.pos },
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/monogram_bitmap.png"),
                    .size = tex.size,
                    .u = encode('1'),
                    .tint = tex.tint,
                },
                ecs.component.Ctr{ .count = 1 },
                ecs.component.Lnk{},
                ecs.component.Str{},
            });

            pos.pos += .{ 6 * tex.size, 0 };
            return true;
        }
    }

    return false;
}

pub fn decrement(world: *ecs.world.World, entity: ecs.entity.Entity) !bool {
    const pos = try world.inspect(entity, ecs.component.Pos);
    const tex = try world.inspect(entity, ecs.component.Tex);
    const ctr = try world.inspect(entity, ecs.component.Ctr);
    const lnk = try world.inspect(entity, ecs.component.Lnk);

    if (world.checkSignature(entity, &.{}, &.{ecs.component.Str})) {
        return ecs.world.WorldError.InvalidInspection;
    }

    if (lnk.child) |child| {
        if (ctr.count == 0) {
            ctr.count = 9;
            tex.u = encode('9');

            if (try decrement(world, child)) {
                if (!world.isAlive(child)) {
                    lnk.child = null;
                }
                pos.pos -= .{ 6 * tex.size, 0 };
                return true;
            }
        } else {
            ctr.count -= 1;
            tex.u -= 1;
        }
    } else {
        if (ctr.count <= 1) {
            if (world.checkSignature(entity, &.{}, &.{ecs.component.Src})) {
                world.kill(entity);
                return true;
            } else {
                ctr.count = 0;
                tex.u = encode('0');
            }
        } else {
            ctr.count -= 1;
            tex.u -= 1;
        }
    }

    return false;
}

/// Moves a counter by some vector.
pub fn move(world: *ecs.world.World, entity: ecs.entity.Entity, velocity: @Vector(2, i32)) !void {
    const pos = try world.inspect(entity, ecs.component.Pos);
    const lnk = try world.inspect(entity, ecs.component.Lnk);

    if (world.checkSignature(entity, &.{}, &.{
        ecs.component.Ctr,
        ecs.component.Tex,
        ecs.component.Str,
    })) {
        return ecs.world.WorldError.InvalidInspection;
    }

    pos.pos += velocity;

    if (lnk.child) |child| {
        try move(world, child, velocity);
    }
}

pub fn reposition(world: *ecs.world.World, entity: ecs.entity.Entity, position: @Vector(2, i32)) !void {
    const pos = try world.inspect(entity, ecs.component.Pos);
    const tex = try world.inspect(entity, ecs.component.Tex);
    const lnk = try world.inspect(entity, ecs.component.Lnk);

    if (world.checkSignature(entity, &.{}, &.{
        ecs.component.Ctr,
        ecs.component.Str,
    })) {
        return ecs.world.WorldError.InvalidInspection;
    }

    var digits_minus_one: i32 = 0;

    var current = lnk.child;

    while (current) |child| {
        const child_lnk = try world.inspect(child, ecs.component.Lnk);

        if (world.checkSignature(entity, &.{}, &.{
            ecs.component.Pos,
            ecs.component.Ctr,
            ecs.component.Tex,
            ecs.component.Str,
        })) {
            return ecs.world.WorldError.InvalidInspection;
        }

        digits_minus_one += 1;
        current = child_lnk.child;
    }

    const velocity = position - pos.pos + [_]i32{ digits_minus_one * 6 * tex.size, 0 };

    pos.pos += velocity;

    if (lnk.child) |child| {
        try move(world, child, velocity);
    }
}
