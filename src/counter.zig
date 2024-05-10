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
    });
}

pub fn increment(world: *ecs.world.World, entity: ecs.entity.Entity) !bool {
    const pos = try world.inspect(entity, ecs.component.Pos);
    const tex = try world.inspect(entity, ecs.component.Tex);
    const ctr = try world.inspect(entity, ecs.component.Ctr);
    const lnk = try world.inspect(entity, ecs.component.Lnk);

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
            });

            pos.pos += .{ 6 * tex.size, 0 };

            return true;
        }
    }

    return false;
}
