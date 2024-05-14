const rl = @import("raylib");
const std = @import("std");
const ecs = @import("ecs/ecs.zig");
const AssetManager = @import("AssetManager.zig");

pub fn encode(char: u8) u8 {
    if (char < 32) unreachable;

    return char - 32;
}

pub fn spawnCounter(world: *ecs.world.World, position: @Vector(2, i32), size: u8, tint: rl.Color) !ecs.entity.Entity {
    return world.spawnWith(.{
        ecs.component.Pos{ .pos = position },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/monogram_bitmap.png"),
            .size = size,
            .tint = tint,
            .u = encode('0'),
        },
        ecs.component.Ctr{},
        ecs.component.Lnk{},
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
