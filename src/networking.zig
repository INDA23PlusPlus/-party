const std = @import("std");
const constants = @import("constants.zig");

const sim = @import("simulation.zig");
const ecs = @import("ecs/world.zig");
const cbor = @import("cbor.zig");

const NetworkingQueue = @import("NetworkingQueue.zig");
const InputMerger = @import("InputMerger.zig");

const ConnectedClient = struct {
    consistent_until: u64 = 0,
    tick_acknowledged: u64 = 0,
    packets_available: u32 = 0,
};

const ConnectionType = enum(u8) {
    unused,
    local,
    remote,
};

const max_net_packet_size = 32768;

const max_unresponded_ticks = 32;
const max_inputs_per_socket_packet = 64;

fn debugPacket(packet: []u8) void {
    // Print the CBOR contents.
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
    input_merger: InputMerger,

    conns_list: [constants.max_connected_count]ConnectedClient = undefined,
    conns_type: [constants.max_connected_count]ConnectionType = [_]ConnectionType{.unused} ** constants.max_connected_count,
    conns_sockets: [constants.max_connected_count]std.posix.socket_t = undefined,
    conns_incoming_packets: [constants.max_connected_count][max_inputs_per_socket_packet]NetworkingQueue.Packet = undefined,
    conns_should_read: [constants.max_connected_count]bool = undefined,

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
        if (!try self.input_merger.remoteUpdate(std.heap.page_allocator, change.player, change.data, change.tick)) {
            // If input was already set, we can just exit early and not resend anything.
            return;
        }

        inline for (&self.conns_list, self.conns_type) |*connection, conn_type| {
            if (conn_type != .unused) {
                connection.consistent_until = @min(connection.consistent_until, change.tick);
            }
        }
    }
};

fn parsePacketFromClient(client_index: usize, server_data: *NetServerData, packet: []u8) !void {
    var client = &server_data.conns_list[client_index];
    var scanner = cbor.Scanner{};
    var ctx = scanner.begin(packet);
    var header = try ctx.readArray();
    std.debug.assert(header.items == 2);
    client.tick_acknowledged = @max(client.tick_acknowledged, try header.readU64());
    //std.debug.print("packet from client with tick ack {}\n", .{new_tick_acknowledged});
    var packets = try header.readArray();
    for (0..packets.items) |_| {
        var packet_ctx = try packets.readArray();
        std.debug.assert(packet_ctx.items == 5);
        const frame_tick_index = try packet_ctx.readU64();
        const player_index = try packet_ctx.readU64();
        const dpad = try packet_ctx.readU64();
        const button_a = try packet_ctx.readU64();
        const button_b = try packet_ctx.readU64();
        try packet_ctx.readEnd();

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
            .player = @truncate(player_index),
        };

        client.packets_available += 1;
    }
    try packets.readEnd();
    try header.readEnd();
}

fn clientConnected(server_data: *NetServerData, conn: std.net.Server.Connection) void {
    std.debug.print("incoming player\n", .{});

    if (server_data.reservSlot()) |slot| {
        server_data.conns_list[slot] = .{};
        server_data.conns_should_read[slot] = false;
        server_data.conns_sockets[slot] = conn.stream.handle;
    } else {
        std.log.warn("too many players", .{});
        conn.stream.close();
    }
}

fn sendUpdatesToLocalClient(networking_queue: *NetworkingQueue, input_merger: *InputMerger, consistent_until: u64, targeted_tick: u64) u64 {
    var new_consistent_until = consistent_until;
    for (consistent_until..targeted_tick) |tick_index| {
        const inputs = input_merger.buttons.items[tick_index];
        const is_certain = input_merger.is_certain.items[tick_index];
        for (inputs, 0..) |packet, player_index| {
            if (!is_certain.isSet(player_index)) {
                continue;
            }

            if (networking_queue.outgoing_data_count >= networking_queue.outgoing_data.len) {
                return new_consistent_until;
            }

            networking_queue.outgoing_data[networking_queue.outgoing_data_count] = .{
                .tick = tick_index,
                .player = @truncate(player_index),
                .data = packet,
            };
            networking_queue.outgoing_data_count += 1;
            new_consistent_until = @max(new_consistent_until, targeted_tick);
        }
    }
    return new_consistent_until;
}

fn sendUpdatesToRemoteClient(fd: std.posix.socket_t, input_merger: *InputMerger, consistent_until: u64, targeted_tick: u64) !u64 {
    var send_buffer: [max_net_packet_size]u8 = undefined;
    const send_amount = targeted_tick - consistent_until;

    var fb = std.io.fixedBufferStream(&send_buffer);
    const writer = fb.writer();
    try cbor.writeArrayHeader(writer, send_amount);
    for (consistent_until..targeted_tick) |tick_index| {
        const inputs = input_merger.buttons.items[tick_index];
        const is_certain = input_merger.is_certain.items[tick_index];

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
        }
    }
    _ = try std.posix.send(fd, send_buffer[0..fb.pos], 0);
    return @max(consistent_until, targeted_tick);
}

fn serverThreadQueueTransfer(server_data: *NetServerData, networking_queue: *NetworkingQueue) !void {
    networking_queue.rw_lock.lock();

    // Ingest the updates from the local-client.
    for (networking_queue.incoming_data[0..networking_queue.incoming_data_count]) |change| {
        try server_data.ingestPlayerInput(change);
    }
    networking_queue.incoming_data_count = 0;

    // Update local tick_acknowledged.
    for (&server_data.conns_list, server_data.conns_type) |*connection, conn_type| {
        if (conn_type == .local) {
            connection.tick_acknowledged = @max(connection.tick_acknowledged, networking_queue.client_acknowledge_tick);
        }
    }

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
    for (&server_data.conns_list, server_data.conns_type, &server_data.conns_sockets) |*connection, conn_type, fd| {
        // Send the missing inputs. But only N at the time.
        const send_start = connection.consistent_until + 1;
        const send_until = @min(server_data.input_merger.buttons.items.len, send_start + max_inputs_per_socket_packet);

        if (send_until <= send_start) {
            // Nothing to send.
            continue;
        }

        if (conn_type == .unused) {
            continue;
        }

        if (connection.tick_acknowledged + max_unresponded_ticks < connection.consistent_until) {
            // We have sent too much without a response, time to wait for a response.
            //std.debug.print("tick ack {} and consistent until {}\n", .{connection.tick_acknowledged, connection.consistent_until});
            continue;
        }

        connection.consistent_until =
            if (conn_type == .local) sendUpdatesToLocalClient(networking_queue, &server_data.input_merger, connection.consistent_until, send_until) else try sendUpdatesToRemoteClient(fd, &server_data.input_merger, connection.consistent_until, send_until);
    }

    networking_queue.rw_lock.unlock();

    //if (server_data.input_history.buttons.items.len == 300 + 1) {
    //    const file = std.io.getStdErr();
    //    const writer = file.writer();
    //    try server_data.input_history.dumpInputs(writer);
    //}
}

/// Sets conns_should_read[index] for any socket that has available data.
/// We also use this code in the client to poll the singular connection to the server.
/// It is nice to reuse platform-level abstraction when possible.
fn pollSockets(conns_type: []ConnectionType, conns_sockets: []std.posix.socket_t, conns_should_read: []bool) void {
    if (@import("builtin").os.tag == .windows) {
        var read_fd_set = std.os.windows.ws2_32.fd_set{
            .fd_array = undefined,
            .fd_count = 0,
        };

        const timeval = std.os.windows.ws2_32.timeval{
            .tv_sec = 0,
            .tv_usec = 1000,
        };

        var fd_count: u32 = 0;
        for (conns_type, conns_sockets) |conn_type, conn_socket| {
            if (conn_type == .remote) {
                std.debug.assert(fd_count < read_fd_set.fd_array.len);
                read_fd_set.fd_array[fd_count] = conn_socket;
                fd_count += 1;
            }
        }
        read_fd_set.fd_count = fd_count;

        const i = std.os.windows.ws2_32.select(0, &read_fd_set, null, null, &timeval);
        if (i <= 0) {
            return;
        }

        for (read_fd_set.fd_array[0..read_fd_set.fd_count]) |fd| {
            // O complexity is n^2. Luckily a read_fd_set can not be larger than 64...
            for (conns_sockets, 0..) |other, conn_index| {
                if (other == fd) {
                    conns_should_read[conn_index] = true;
                }
            }
        }
    } else {
        const INT_EVENTS = std.posix.POLL.IN | std.posix.POLL.HUP | std.posix.POLL.PRI;
        var poll_fds: [64]std.posix.pollfd = undefined;
        for (&poll_fds) |*poll_fd| {
            poll_fd.fd = -1;
            poll_fd.revents = 0;
            poll_fd.events = INT_EVENTS;
        }

        var fd_count: usize = 0;
        for (conns_type, conns_sockets) |conn_type, conn_socket| {
            if (conn_type == .remote) {
                std.debug.assert(fd_count < poll_fds.len);
                poll_fds[fd_count].fd = conn_socket;
                fd_count += 1;
            }
        }

        const i = std.posix.poll(&poll_fds, 1) catch {
            std.debug.print("std.posix.poll() failed\n", .{});
            return;
        };

        if (i <= 0) {
            return;
        }

        for (poll_fds[0..fd_count]) |poll_fd| {
            for (conns_sockets, 0..) |other, conn_index| {
                if (other == poll_fd.fd and poll_fd.revents & INT_EVENTS != 0) {
                    conns_should_read[conn_index] = true;
                }
            }
        }
    }
}

fn readFromSockets(server_data: *NetServerData) void {
    var read_buffer: [max_net_packet_size]u8 = undefined;
    pollSockets(&server_data.conns_type, &server_data.conns_sockets, &server_data.conns_should_read);
    for (&server_data.conns_list, server_data.conns_sockets, server_data.conns_type, server_data.conns_should_read, 0..) |*connection, fd, conn_type, should_read, conn_index| {
        if (conn_type != .remote) {
            continue;
        }
        if (!should_read) {
            continue;
        }
        server_data.conns_should_read[conn_index] = false;

        _ = connection;
        const length = std.posix.read(fd, &read_buffer) catch 0;
        if (length == 0) {
            server_data.conns_type[conn_index] = .unused;
            // TODO: Disconnect player. But don't use conn_index.
            //server_data.input_merger.remoteUpdate(std.heap.page_allocator, , new_state: input.PlayerInputState, tick: u64)
            std.posix.close(fd);
            continue;
        }

        //std.debug.print("reading from player {d} length {d}", .{ conn_index, length });
        //debugPacket(read_buffer[0..length]);

        parsePacketFromClient(conn_index, server_data, read_buffer[0..length]) catch |e| {
            std.debug.print("error while parsing packet of player {d}: {any}\n", .{ conn_index, e });
        };
    }
}

fn serverThread(networking_queue: *NetworkingQueue) !void {
    var server_data = NetServerData{
        .input_merger = try InputMerger.init(std.heap.page_allocator),
    };
    //defer server_data.input_history.deinit(std.heap.page_allocator);

    server_data.conns_type[0] = .local;

    const address = try std.net.Address.parseIp("0.0.0.0", 8080);
    var listening = try address.listen(.{ .force_nonblocking = true });

    while (true) {
        if (listening.accept()) |new_client| {
            clientConnected(&server_data, new_client);
        } else |_| {}

        readFromSockets(&server_data);

        // TODO: Take clock timestamp
        try serverThreadQueueTransfer(&server_data, networking_queue);

        // Debug thing. Remove later.
        const rl = @import("raylib");
        if (rl.isKeyPressed(rl.KeyboardKey.key_o)) {
            const file = std.io.getStdErr();
            const writer = file.writer();
            try server_data.input_merger.dumpInputs((server_data.input_merger.buttons.items.len >> 9) << 9, writer);
        }

        std.time.sleep(std.time.ns_per_ms * 19);
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

const PollerForClient = struct {
    fd: [1]std.posix.socket_t,
    connection: [1]ConnectionType = .{ConnectionType.remote},
    should_read: [1]bool = .{false},
};

fn clientThread(networking_queue: *NetworkingQueue, hostname: []const u8) !void {
    // We need the GPA because tcpConnectToHost needs to store the DNS lookups somewhere.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const stream = try std.net.tcpConnectToHost(alloc, hostname, 8080);
    var poller = PollerForClient{ .fd = .{stream.handle} };

    std.debug.print("connection established\n", .{});
    var newest_input_tick: u64 = 0;

    while (true) {
        var incoming_packet_buf: [max_net_packet_size]u8 = undefined;
        pollSockets(&poller.connection, &poller.fd, &poller.should_read);
        const incoming_packet_len = if (poller.should_read[0]) try stream.read(&incoming_packet_buf) else 0;
        const incoming_packet = incoming_packet_buf[0..incoming_packet_len];

        // Reset the poller. We don't care if it was ever set.
        poller.should_read[0] = false;

        networking_queue.rw_lock.lock();

        if (incoming_packet_len > 0) {
            const possibly_newer = try handlePacketFromServer(networking_queue, incoming_packet);
            newest_input_tick = @max(possibly_newer, newest_input_tick);
        }

        var write_buffer: [max_net_packet_size]u8 = undefined;
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

        // TODO: Ideally, we avoid sleeping and either awake from changes to networking_queue or activity on stream.
        std.time.sleep(std.time.ns_per_ms * 4);
    }
}

pub fn startClient(networking_queue: *NetworkingQueue, hostname: []const u8) !void {
    _ = try std.Thread.spawn(.{}, clientThread, .{ networking_queue, hostname });
}
