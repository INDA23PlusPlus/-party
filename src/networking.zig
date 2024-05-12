// Let it be known that the complexity of this code really isn't something I am proud of.
// TODO: Keep track of old state and request resimulation

const std = @import("std");
const constants = @import("constants.zig");

const sim = @import("simulation.zig");
const ecs = @import("ecs/world.zig");
const cbor = @import("cbor.zig");

const NetworkingQueue = @import("NetworkingQueue.zig");
const InputConsolidation = @import("InputConsolidation.zig");

const ConnectedClient = struct {
    read_buffer: [256]u8,
    consistent_until: u64,
    tick_acknowledged: u64,
    packets_available: u32,
};

const ConnectionType = enum(u8) {
    unused,
    local,
    remote,
};

// TODO: Use in conns_write_buffers.
const max_net_packet_size = 32768;

fn debugPacket(packet: []u8) void {
    var debug_log_buffer: [1024]u8 = undefined;
    var debug_fb = std.io.fixedBufferStream(&debug_log_buffer);
    const debug_writer = debug_fb.writer();
    var scanner = cbor.Scanner{};
    var ctx = scanner.begin(packet);
    const debug_len = ctx.toString(debug_writer) catch |e| {
        const formatter = std.fmt.fmtSliceHexUpper(packet);
        std.debug.print("could not parse package ({any}): {any}\n", .{ e, formatter });
        return;
    };
    std.debug.print("parsed package: {s}\n", .{debug_log_buffer[0..debug_len]});
}

const NetServerData = struct {
    input_history: InputConsolidation,

    conns_list: [constants.max_connected_count]ConnectedClient = undefined,
    conns_type: [constants.max_connected_count]ConnectionType = [_]ConnectionType{.unused} ** constants.max_connected_count,
    conns_incoming_packets: [constants.max_connected_count][20]NetworkingQueue.Packet = undefined,
    conns_write_buffers: [constants.max_connected_count][1024]u8 = undefined,
    conns_read_buffers: [constants.max_connected_count][1024]u8 = undefined,

    networking_queue: *NetworkingQueue,

    fn reservSlot(self: *NetServerData) ?usize {
        for (self.conns_type, 0..) |t, i| {
            if (t == .unused) {
                self.conns_type[i] = .remote;
                return i;
            }
        }
        return null;
    }

    fn ingestPlayerInput(self: *NetServerData, change: NetworkingQueue.Packet) !void {
        if (!try self.input_history.remoteUpdate(std.heap.page_allocator, change.player, change.data, change.tick)) {
            // If input was already set, we can just exit early and not resend anything.
            return;
        }

        inline for (&self.conns_list, self.conns_type) |*connection, conn_type| {
            if (conn_type == .remote) {
                connection.consistent_until = @min(connection.consistent_until, change.tick);
            }
        }
    }
};

fn parsePacketFromClient(client_index: usize, server_data: *NetServerData, packet: []u8) !void {
    std.debug.print("message from client\n", .{});
    var client = &server_data.conns_list[client_index];
    var scanner = cbor.Scanner{};
    var ctx = scanner.begin(packet);
    var header = try ctx.readArray();
    client.tick_acknowledged = try header.readU64();
    std.debug.print("tick_ack: {d}\n", .{client.tick_acknowledged});
    var packets = try header.readArray();
    for (0..packets.items) |_| {
        var packet_ctx = try packets.readArray();
        const frame_tick_index = try packet_ctx.readU64();
        const dpad = try packet_ctx.readU64();
        const button_a = try packet_ctx.readU64();
        const button_b = try packet_ctx.readU64();
        try packets.readEnd();

        if (client.packets_available >= server_data.conns_incoming_packets.len) {
            continue;
        }

        server_data.conns_incoming_packets[client_index][client.packets_available] = .{
            .tick = @truncate(frame_tick_index),
            .data = .{
                .dpad = @enumFromInt(dpad),
                .button_a = @enumFromInt(button_a),
                .button_b = @enumFromInt(button_b),
            },
            .player = @truncate(client_index),
        };

        client.packets_available += 1;
    }
    try packets.readEnd();
    try header.readEnd();
}

// TODO: Readd
// fn handlePacketFromClient(client_index_raw: ?*ConnectedClientIndex, l: *xev.Loop, _: *xev.Completion, s: xev.TCP, read_buffer: xev.ReadBuffer, packet_size_res: xev.ReadError!usize) xev.CallbackAction {
//     _ = s;
//     var server_data = loopToServerData(l);
//     const client_index = fromClientIndex(client_index_raw);
//     var client = &server_data.conns_list[client_index];
// 
//     const packet_size = packet_size_res catch |e| {
//         server_data.conns_type[client_index] = .unused;
//         client.stream.shutdown(l, &client.read_completion, void, null, afterOverfullDisconnect);
//         std.debug.print("error: {any}\n", .{e});
//         return .disarm;
//     };
// 
//     const packet = read_buffer.slice[0..packet_size];
// 
//     //debugPacket(packet);
//     parsePacketFromClient(client_index, server_data, packet) catch |e| {
//         std.debug.print("error while handling package from client: {any}\n", .{e});
//     };
// 
//     // TODO: Parse packet and ingest into input_history.
// 
//     //std.debug.print("message from ({d}): {s}\n", .{ fromClientIndex(client_index), packet });
// 
//     //const write_buffer: xev.WriteBuffer = .{ .array = .{
//     //    .array = [2]u8{ 'h', 'i' } ** 16,
//     //    .len = 2,
//     //} };
//     //s.write(l, &client.write_completion, write_buffer, void, null, writeNoop);
// 
//     return .rearm;
// }
// 
// fn afterOverfullDisconnect(_: ?*void, l: *xev.Loop, _: *xev.Completion, _: xev.TCP, _: xev.ShutdownError!void) xev.CallbackAction {
//     const server_data = loopToServerData(l);
//     startNewConnectionHandler(server_data);
//     return .disarm;
// }
// 
// fn startNewConnectionHandler(server_data: *NetServerData) void {
//     server_data.listener.accept(&server_data.loop, &server_data.accept_completion, void, null, clientConnected);
// }
// 
// fn clientConnected(_: ?*void, l: *xev.Loop, _: *xev.Completion, r: xev.TCP.AcceptError!xev.TCP) xev.CallbackAction {
//     const server_data = loopToServerData(l);
// 
//     var stream = r catch |e| {
//         std.debug.print("e: {any}", .{e});
//         return .disarm;
//     };
// 
//     std.debug.print("incoming player\n", .{});
// 
//     if (server_data.reservSlot()) |slot| {
//         server_data.conns_list[slot].packets_available = 0;
//         server_data.conns_list[slot].stream = stream;
//         server_data.conns_list[slot].consistent_until = 1;
//         server_data.conns_list[slot].tick_acknowledged = 0;
//         const completion = &server_data.conns_list[slot].read_completion;
//         const buffer = &server_data.conns_list[slot].read_buffer;
//         stream.read(l, completion, .{ .slice = buffer }, ConnectedClientIndex, toClientIndex(slot), handlePacketFromClient);
// 
//         startNewConnectionHandler(server_data);
//         return .disarm;
//     } else {
//         std.log.warn("too many players", .{});
//         stream.shutdown(l, &server_data.accept_completion, void, null, afterOverfullDisconnect);
//         return .disarm;
//     }
// }

fn serverThreadQueueTransfer(server_data: *NetServerData, networking_queue: *NetworkingQueue) !void {
    networking_queue.rw_lock.lock();

    // Ingest the updates from the local-client.
    for (networking_queue.incoming_data[0..networking_queue.incoming_data_count]) |change| {
        try server_data.ingestPlayerInput(change);
    }
    networking_queue.incoming_data_count = 0;

    // Ingest the updates from the connected clients.
    for (&server_data.conns_list, server_data.conns_type, &server_data.conns_incoming_packets) |*connection, conn_type, *conns_packets| {
        if (conn_type != .remote) {
            continue;
        }
        for (conns_packets[0..connection.packets_available]) |change| {
            try server_data.ingestPlayerInput(change);
        }
        connection.packets_available = 0;
    }

    // Send the updates to the clients.
    for (&server_data.conns_list, server_data.conns_type, &server_data.conns_write_buffers) |*connection, conn_type, *write_buffer| {
        // Send the missing inputs. But only N at the time.
        const send_until = @min(server_data.input_history.buttons.items.len, connection.consistent_until + 40);
        const input_tick_count = send_until -| connection.consistent_until;

        if (conn_type == .local) {
            for (connection.consistent_until..connection.consistent_until + input_tick_count) |tick_number| {
                const inputs = server_data.input_history.buttons.items[tick_number];
                for (inputs, 0..) |packet, player_index| {
                    // TODO: Reduce the nesting.
                    if (networking_queue.outgoing_data_count >= networking_queue.outgoing_data.len) {
                        continue;
                    }
                    networking_queue.outgoing_data[networking_queue.outgoing_data_count] = .{
                        .tick = tick_number,
                        .player = @truncate(player_index),
                        .data = packet,
                    };
                    networking_queue.outgoing_data_count += 1;
                }
            }
        }

        if (conn_type != .remote) {
            continue;
        }


        // TODO: make 20 a constant
        if (connection.tick_acknowledged + 20 < connection.consistent_until) {
            // We have sent too much without a response, time to wait for a response.
            continue;
        }

        // if (connection.write_completion.state() == .active) {
        //     // We are still writing data.
        //     continue;
        // }


        var fb = std.io.fixedBufferStream(write_buffer);
        const writer = fb.writer();
        try cbor.writeArrayHeader(writer, input_tick_count);
        const targeted_tick = connection.consistent_until + input_tick_count;
        for (connection.consistent_until..targeted_tick) |tick_index| {
            const inputs = server_data.input_history.buttons.items[tick_index];
            const is_certain = server_data.input_history.is_certain.items[tick_index];

            try cbor.writeArrayHeader(writer, 2);
            try cbor.writeUint(writer, tick_index);
            try cbor.writeArrayHeader(writer, is_certain.count());
            for (0..constants.max_player_count) |player| {
                if (!is_certain.isSet(player)) {
                    continue;
                }
                const input = inputs[player];
                try cbor.writeArrayHeader(writer, 4);
                try cbor.writeUint(writer, player);
                try cbor.writeUint(writer, @intFromEnum(input.dpad));
                try cbor.writeUint(writer, @intFromEnum(input.button_a));
                try cbor.writeUint(writer, @intFromEnum(input.button_b));

                std.debug.print("sending: to player ?? tick {d} from player {d} with dpad {s}\n", .{tick_index, player, @tagName(input.dpad)});
            }
        }
        // TODO: Readd
        //connection.stream.write(&server_data.loop, &connection.write_completion, .{ .slice = write_buffer[0..fb.pos] }, void, null, writeNoop);
        connection.consistent_until = targeted_tick;
    }

    networking_queue.rw_lock.unlock();

    //if (server_data.input_history.buttons.items.len == 300 + 1) {
    //    const file = std.io.getStdErr();
    //    const writer = file.writer();
    //    try server_data.input_history.dumpInputs(writer);
    //}
}

fn serverThread(networking_queue: *NetworkingQueue) !void {
    var server_data = NetServerData{ .input_history = undefined, .networking_queue = networking_queue };
    server_data.conns_type[0] = .local;

    server_data.input_history = try InputConsolidation.init(std.heap.page_allocator);
    //defer server_data.input_history.deinit(std.heap.page_allocator);

    //const address = try std.net.Address.parseIp("0.0.0.0", 8080);
    //server_data.listener = try xev.TCP.init(address);
    //try server_data.listener.bind(address);
    //try server_data.listener.listen(16);
    //startNewConnectionHandler(&server_data);

    // If this isn't done, then connections can not be made on Windows.
    //try server_data.loop.run(.once);

    while (true) {
        // TODO: Take clock timestamp
        try serverThreadQueueTransfer(&server_data, networking_queue);
        std.time.sleep(std.time.ns_per_ms * 20);
        // TODO: Take clock timestamp
        // TODO: Compare these then sleep a bit to lock the ticks per second.
    }
}

pub fn startServer(networking_queue: *NetworkingQueue) !void {
    _ = try std.Thread.spawn(.{}, serverThread, .{networking_queue});
}

fn handlePacketFromServer(networking_queue: *NetworkingQueue, packet: []u8) !u64 {
    var scanner = cbor.Scanner{};
    var ctx = scanner.begin(packet);
    var all_packets = try ctx.readArray();
    var newest_input_tick: u64 = 0;
    for (0..all_packets.items) |_| {
        var tick_info = try all_packets.readArray();
        std.debug.assert(tick_info.items == 2);
        const input_tick_index = try tick_info.readU64();
        newest_input_tick = @max(newest_input_tick, input_tick_index);
        var all_inputs = try tick_info.readArray();
        for (0..all_inputs.items) |_| {
            var player_input = try all_inputs.readArray();
            std.debug.assert(player_input.items == 4);
            const player_i = try player_input.readU64();
            const dpad = try player_input.readU64();
            const button_a = try player_input.readU64();
            const button_b = try player_input.readU64();
            try player_input.readEnd();


            if (networking_queue.outgoing_data_count >= networking_queue.outgoing_data.len) {
                continue;
            }

            networking_queue.outgoing_data[networking_queue.outgoing_data_count] = .{
                .tick = @truncate(input_tick_index),
                .data = .{
                    .dpad = @enumFromInt(dpad),
                    .button_a = @enumFromInt(button_a),
                    .button_b = @enumFromInt(button_b),
                },
                .player = @truncate(player_i),
            };
            //std.debug.print("received dpad: {any} for player {d} and tick {d}\n", .{networking_queue.outgoing_data[networking_queue.outgoing_data_count].data.dpad, player_i, input_tick_index});

            networking_queue.outgoing_data_count += 1;
        }
        try all_inputs.readEnd();
        try tick_info.readEnd();
    }
    try all_packets.readEnd();

    return newest_input_tick;
}

fn clientThread(networking_queue: *NetworkingQueue) !void {
    // The client doesn't currently do evented IO. I don't think it will be necessary.

    var mem: [1024]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&mem);
    const allocator = alloc.allocator();
    const stream = try std.net.tcpConnectToHost(allocator, "127.0.0.1", 8080);
    // TODO: Use non-blocking reads such that input is always send even if other inputs are still in air.
    std.debug.print("connection established\n", .{});
    var newest_input_tick: u64 = 0;

    //std.time.sleep(std.time.ns_per_s * 1);
    while (true) {
        var incoming_packet_buf: [1024]u8 = undefined;
        const incoming_packet_len = try stream.read(&incoming_packet_buf);
        const incoming_packet = incoming_packet_buf[0..incoming_packet_len];

        //debugPacket(incoming_packet);

        // TODO: Parse packets.

        networking_queue.rw_lock.lock();

        const possibly_newer = try handlePacketFromServer(networking_queue, incoming_packet);
        newest_input_tick = @max(possibly_newer, newest_input_tick);

        var write_buffer: [4096]u8 = undefined;
        var fb = std.io.fixedBufferStream(&write_buffer);
        const writer = fb.writer();

        try cbor.writeArrayHeader(writer, 2);
        try cbor.writeUint(writer, newest_input_tick);
        try cbor.writeArrayHeader(writer, networking_queue.incoming_data_count);
        for (networking_queue.incoming_data[0..networking_queue.incoming_data_count]) |packet| {
            try cbor.writeArrayHeader(writer, 5);
            try cbor.writeUint(writer, packet.tick);
            try cbor.writeUint(writer, packet.player);
            try cbor.writeUint(writer, @intFromEnum(packet.data.dpad));
            try cbor.writeUint(writer, @intFromEnum(packet.data.button_a));
            try cbor.writeUint(writer, @intFromEnum(packet.data.button_b));
        }
        networking_queue.incoming_data_count = 0;
        _ = try stream.write(write_buffer[0..fb.pos]);

        networking_queue.rw_lock.unlock();
        std.time.sleep(std.time.ns_per_ms * 20);
    }
}

pub fn startClient(networking_queue: *NetworkingQueue) !void {
    _ = try std.Thread.spawn(.{}, clientThread, .{networking_queue});
}
