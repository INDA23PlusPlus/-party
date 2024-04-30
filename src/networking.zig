// TODO: Still heavily a work in progress.
// TODO: Handle disconnects (set input state of the player as disconnected)
// TODO: Parse packets and send packets
// TODO: Keep track of old state and request resimulation

const std = @import("std");
const constants = @import("constants.zig");
const xev = @import("xev");

const sim = @import("simulation.zig");
const ecs = @import("ecs/world.zig");
const NetworkingQueue = @import("NetworkingQueue.zig");
const InputConsolidation = @import("InputConsolidation.zig");

const NetData = struct {
    // Any common data.
    // No clue if even needed.
};

const ConnectedClient = struct {
    stream: xev.TCP,
    read_completion: xev.Completion,
    write_completion: xev.Completion,
    read_buffer: [256]u8,
    consistent_until: u64,
    packets_available: u64,
};

const ConnectionType = enum(u8) {
    unusued,
    local,
    remote,
};

const NetServerData = struct {
    common: NetData = NetData{},
    input_history: InputConsolidation,

    conns_list: [constants.max_connected_count]ConnectedClient = undefined,
    conns_type: [constants.max_connected_count]ConnectionType = [_]ConnectionType{.Unused} ** constants.max_connected_count,
    conns_packets: [constants.max_connected_count][20]InputConsolidation.Packet = undefined,

    loop: xev.Loop,
    accept_completion: xev.Completion = undefined,
    listener: xev.TCP = undefined,

    fn reservSlot(self: *NetServerData) ?usize {
        for (self.conns_type, 0..) |t, i| {
            if (t == .unused) {
                self.conns_type[i] = .remote;
                return i;
            }
        }
        return null;
    }

    fn ingestPlayerInput(self: *const NetServerData, change: NetworkingQueue.Packet) void {
        // TODO: Could be optimized such that we do not need to loop for every ingestPlayerInput.

        _ = try self.input_history.remoteUpdate(std.heap.page_allocator, change.player, change.data, change.tick);
        inline for (self.conns_list, self.slot_occupied) |*connection, occupied| {
            if (!occupied) {
                continue;
            }
            connection.consistent_until = @min(connection.consistent_until, change.tick);
        }
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

    // TODO: Parse packet and ingest into input_history.

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
        server_data.conns_list[slot].packets_available = 0;
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

fn serverThread(networking_queue: *NetworkingQueue) !void {
    var server_data = NetServerData{ .loop = undefined };
    server_data.conns_type[0] == .local;
    server_data.loop = try xev.Loop.init(.{ .entries = 128 });
    defer server_data.loop.deinit();

    server_data.input_history.init(std.heap.page_allocator);
    //defer server_data.input_history.deinit(std.heap.page_allocator);

    const address = try std.net.Address.parseIp("0.0.0.0", 8080);
    server_data.listener = try xev.TCP.init(address);
    try server_data.listener.bind(address);
    try server_data.listener.listen(16);
    startNewConnectionHandler(&server_data);

    //try server_data.loop.run(.until_done);
    while (true) {
        // TODO: Take clock timestamp

        // Give thethreads a chance to work.
        try server_data.loop.run(.once);

        networking_queue.rw_lock.lock();

        // Ingest the updates from the local-client.
        for (networking_queue.incoming_data[0..networking_queue.incoming_data_len]) |change| {
            server_data.ingestPlayerInput(change);
        }
        networking_queue.incoming_data_len = 0;

        // Ingest the updates from the connected clients.
        inline for (server_data.conns_list, server_data.conns_type, server_data.conns_packets) |*connection, conn_type, *conns_packets| {
            if (conn_type != .remote) {
                continue;
            }
            for (conns_packets[0..connection.packets_available]) |change| {
                server_data.ingestPlayerInput(change);
            }
            connection.packets_available = 0;
        }

        // Send the updates to the clients.
        inline for (server_data.conns_list, server_data.conns_type) |connection, conn_type| {
            // Send the missing inputs. But only N at the time.
            const send_until = @min(server_data.input_history.buttons.items.len, connection.consistent_until + 40);

            if (conn_type == .local) {
                for (connection.consistent_until .. send_until) |tick_number| {
                    const packet = server_data.input_history.buttons[tick_number];
                    _ = packet;
                }
            }

            if (conn_type != .remote) {
                continue;
            }
            if (connection.write_completion.state() == .active) {
                // We are still writing data.
                continue;
            }

            // TODO: Actually send the data to remote peers.
        }

        networking_queue.rw_lock.unlock();

        std.time.sleep(std.time.ns_per_ms * 20);
        //
        // TODO: Take clock timestamp
        // TODO: Compare these then sleep a bit to lock the ticks per second.
    }
}

pub fn startServer(networking_queue: *NetworkingQueue) !void {
    _ = try std.Thread.spawn(.{}, serverThread, .{networking_queue});
}

const NetClientData = struct {
    common: NetData,
};

fn clientThread(networking_queue: *NetworkingQueue) !void {
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

        // TODO: Parse packets.

        networking_queue.rw_lock.lock();

        networking_queue.rw_lock.unlock();
        std.time.sleep(std.time.ns_per_ms * 20);
    }
}

pub fn startClient(networking_queue: *NetworkingQueue) !void {
    _ = try std.Thread.spawn(.{}, clientThread, .{networking_queue});
}
