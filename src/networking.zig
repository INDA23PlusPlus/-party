// TODO: Still heavily a work in progress.
// TODO: Handle disconnects (set input state of the player as disconnected)
// TODO: Parse packets and send packets
// TODO: Keep track of old state and request resimulation

const std = @import("std");
const constants = @import("constants.zig");
const xev = @import("xev");

const ecs = @import("ecs/world.zig");

const NetData = struct {
    // Any common data.
    // No clue if even needed.
};

const ConnectedClient = struct {
    stream: xev.TCP,
    read_completion: xev.Completion,
    write_completion: xev.Completion,
    read_buffer: [256]u8,
};

const NetServerData = struct {
    common: NetData = NetData{},
    loop: xev.Loop,
    conns_list: [constants.max_player_count]ConnectedClient = undefined,
    slot_occupied: [constants.max_player_count]bool = [_]bool{false} ** constants.max_player_count,
    accept_completion: xev.Completion = undefined,
    listener: xev.TCP = undefined,

    fn reservSlot(self: *NetServerData) ?usize {
        for (self.slot_occupied, 0..) |occupied, i| {
            if (!occupied) {
                self.slot_occupied[i] = true;
                return i;
            }
        }
        return null;
    }
};

const ConnectedClientIndex = opaque {};
pub fn fromClientIndex(index: ?*ConnectedClientIndex) usize {
    return @intFromPtr(index);
}
pub fn toClientIndex(i: usize) ?*ConnectedClientIndex {
    return @ptrFromInt(i);
}

fn loopToServerData(loop: *xev.Loop) *NetServerData {
    return @fieldParentPtr(NetServerData, "loop", loop);
}

fn writeNoop(_: ?*void, _: *xev.Loop, _: *xev.Completion, _: xev.TCP, _: xev.WriteBuffer, _: xev.WriteError!usize) xev.CallbackAction {
    return .disarm;
}

fn clientMessage(client_index: ?*ConnectedClientIndex, l: *xev.Loop, _: *xev.Completion, s: xev.TCP, read_buffer: xev.ReadBuffer, packet_size_res: xev.ReadError!usize) xev.CallbackAction {
    var server_data = loopToServerData(l);
    var client = &server_data.conns_list[fromClientIndex(client_index)];

    const packet_size = packet_size_res catch |e| {
        server_data.slot_occupied[fromClientIndex(client_index)] = false;
        client.stream.shutdown(l, &client.read_completion, void, null, afterOverfullDisconnect);
        std.debug.print("error: {any}\n", .{e});
        return .disarm;
    };

    const packet = read_buffer.slice[0..packet_size];

    std.debug.print("message from ({d}): {s}\n", .{ fromClientIndex(client_index), packet });

    const write_buffer: xev.WriteBuffer = .{ .array = .{
        .array = [2]u8{ 'h', 'i' } ** 16,
        .len = 2,
    } };
    s.write(l, &client.write_completion, write_buffer, void, null, writeNoop);

    return .rearm;
}

fn afterOverfullDisconnect(_: ?*void, l: *xev.Loop, _: *xev.Completion, _: xev.TCP, _: xev.ShutdownError!void) xev.CallbackAction {
    const server_data = loopToServerData(l);
    startNewConnectionHandler(server_data);
    return .disarm;
}

fn startNewConnectionHandler(server_data: *NetServerData) void {
    server_data.listener.accept(&server_data.loop, &server_data.accept_completion, void, null, clientConnected);
}

fn clientConnected(_: ?*void, l: *xev.Loop, _: *xev.Completion, r: xev.TCP.AcceptError!xev.TCP) xev.CallbackAction {
    const server_data = loopToServerData(l);

    var stream = r catch |e| {
        std.debug.print("e: {any}", .{e});
        return .disarm;
    };

    std.debug.print("incoming player\n", .{});

    if (server_data.reservSlot()) |slot| {
        server_data.conns_list[slot].stream = stream;
        const completion = &server_data.conns_list[slot].read_completion;
        const buffer = &server_data.conns_list[slot].read_buffer;
        stream.read(l, completion, .{ .slice = buffer }, ConnectedClientIndex, toClientIndex(slot), clientMessage);

        startNewConnectionHandler(server_data);
        return .disarm;
    } else {
        std.log.warn("too many players", .{});
        stream.shutdown(l, &server_data.accept_completion, void, null, afterOverfullDisconnect);
        return .disarm;
    }
}

fn serverThread(rendered_world: *ecs.SharedWorld) !void {
    var server_data = NetServerData{ .loop = undefined };
    server_data.loop = try xev.Loop.init(.{ .entries = 128 });
    defer server_data.loop.deinit();

    const address = try std.net.Address.parseIp("0.0.0.0", 8080);
    server_data.listener = try xev.TCP.init(address);
    try server_data.listener.bind(address);
    try server_data.listener.listen(16);
    startNewConnectionHandler(&server_data);

    // TODO: Create a server world which will be copied to the rendered_world.

    //try server_data.loop.run(.until_done);
    while (true) {
        // TODO: Take clock timestamp
        try server_data.loop.run(.once);
        // TODO: Copy the local input and treat any changes the same way as remote input changes.

        rendered_world.rw_lock.lock();
        // Perform the required re-simulations.
        // TODO: Copy the real world to the rendered world.
        rendered_world.rw_lock.unlock();
        //
        // TODO: Take clock timestamp
        // TODO: Compare these then sleep a bit to lock the ticks per second.

    }
}

pub fn startServer(rendered_world: *ecs.SharedWorld) !void {
    _ = try std.Thread.spawn(.{}, serverThread, .{rendered_world});
}

const NetClientData = struct {
    common: NetData,
};

fn clientThread(predicted_world: *ecs.SharedWorld) !void {
    // The client doesn't currently do evented IO. I don't think it will be necessary.

    var mem: [1024]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&mem);
    const allocator = alloc.allocator();
    const stream = try std.net.tcpConnectToHost(allocator, "127.0.0.1", 8080);
    _ = try stream.write("hi");

    //std.time.sleep(std.time.ns_per_s * 1);
    while (true) {
        var packet_buf: [1024]u8 = undefined;
        std.debug.print("begin read\n", .{});
        const packet_len = try stream.read(&packet_buf);
        const packet = packet_buf[0..packet_len];
        std.debug.print("received: {s}\n", .{packet});
        _ = try stream.write("hi");

        // TODO: Parse the new world.
        predicted_world.rw_lock.lock();
        // TODO: Get the current tick number from predicted_world.
        // TODO: Copy the new world to the predicted world.
        // TODO: Simulate the world up to the same point (if it isn't too far off).
        // TODO: Copy the newly simulated_world to the predicted_world.
        predicted_world.rw_lock.unlock();
    }
}

pub fn startClient(predicted_world: *ecs.SharedWorld) !void {
    _ = try std.Thread.spawn(.{}, clientThread, .{predicted_world});
}
