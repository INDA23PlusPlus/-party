const std = @import("std");
const ecs = @import("ecs/ecs.zig");
const AssetManager = @import("AssetManager.zig");

pub fn encode(char: u8) u8 {
    if (char < 32) unreachable;

    return char - 32;
}

pub fn spawnCounter(world: *ecs.world.World, position: @Vector(2, i32), size: u8) !ecs.entity.Entity {
    return world.spawnWith(.{
        ecs.component.Pos{ .pos = position },
        ecs.component.Tex{
            .texture_hash = AssetManager.pathHash("assets/monogram_bitmap.png"),
            .size = size,
            .u = encode('0'),
        },
        ecs.component.Ctr{},
        ecs.component.Lnk{},
        ecs.component.Nub{},
    });
}

pub fn increment(world: *ecs.world.World, entity: ecs.entity.Entity) !void {
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
            try increment(world, child);
        } else {
            lnk.child = try world.spawnWith(.{
                ecs.component.Pos{ .pos = pos.pos + [2]i32{ -6, 0 } },
                ecs.component.Tex{
                    .texture_hash = AssetManager.pathHash("assets/monogram_bitmap.png"),
                    .size = tex.size,
                    .u = encode('1'),
                },
                ecs.component.Ctr{ .count = 1 },
                ecs.component.Lnk{},
            });
        }
    }
}
