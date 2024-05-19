const std = @import("std");
const constants = @import("constants.zig");

const sim = @import("simulation.zig");
const ecs = @import("ecs/world.zig");
const cbor = @import("cbor.zig");
const input = @import("input.zig");

const NetworkingQueue = @import("NetworkingQueue.zig");
const InputMerger = @import("InputMerger.zig");

const ConnectedClient = struct {
    consistent_until: u64 = 1,
    tick_acknowledged: u64 = 0,
};

const ConnectionType = enum(u8) {
    /// The connection/client slot can be assigned to a new connection.
    empty,

    /// This slot is reserved for the local client.
    local,

    /// Already occupied by a remote client.
    remote,
};

const max_net_packet_size = 65535 - 8;

const max_input_packets_per_socket = 64;
const max_packets_to_send = 256;
const max_unresponded_ticks = 128 + 64;



fn debugPacket(packet: []const u8) void {
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

const PacketBuffer = struct {
    buffer: [max_net_packet_size * 2]u8 = undefined,
    index: u32 = 0,
    to_remove: u32 = 0,

    inline fn toPacket(self: *PacketBuffer, to_add: []const u8) []const u8 {
        // Move old packet out of the way!
        const old_to_remove = self.to_remove;
        if (old_to_remove > 0) {
            std.mem.copyForwards(u8, self.buffer[0..self.index], self.buffer[self.to_remove..self.index]);
            self.index -= old_to_remove;
            self.to_remove = 0;
        }

        std.debug.assert(self.to_remove == 0);

        if (to_add.len + self.index > self.buffer.len) {
            std.debug.panic("packet buffer will overflow", .{});
        }

        // Regions do not overlap, so this is safe.
        if (to_add.len != 0) {
            @memcpy(self.buffer[self.index .. self.index + to_add.len], to_add);
            self.index += @truncate(to_add.len);
        }

        if (self.index < 4) {
            // Not even the packet length has arrived... Sigh.
            //std.debug.print("waiting for length {d}\n", .{self.index});
            return "";
        }

        const expected_packet_len = std.mem.readInt(u32, self.buffer[0..4], std.builtin.Endian.little);
        const with_header_len = expected_packet_len + 4;

        if (with_header_len > self.index) {
            // Full packet has not arrvied yet.
            //std.debug.print("waiting for packet {d} {d}\n", .{ with_header_len, self.index });
            return "";
        }

        //std.debug.print("reading package of size {d} {d} {d}\n", .{ expected_packet_len, self.index, self.to_remove });

        self.to_remove = with_header_len;
        return self.buffer[4..with_header_len];
    }
};

const NetServerData = struct {
    input_merger: InputMerger,

    /// The connection status of every client/connection slot.
    conns_type: [constants.max_connected_count]ConnectionType = [_]ConnectionType{.empty} ** constants.max_connected_count,

    /// Some smaller flags for every client. TODO: Perhaps each field could become its own array
    conns_list: [constants.max_connected_count]ConnectedClient = undefined,

    /// The underlying OS handles for every client.
    conns_sockets: [constants.max_connected_count]std.posix.socket_t = undefined,

    /// Because TCP over IP is a stream protocol we must chunk the packets using a PacketBuffer.
    conns_packet_buffer: [constants.max_connected_count]PacketBuffer = undefined,

    /// Client bandwith in packets per send decided by if client has to throw away packets or not.
    conns_max_packets_per_send: [constants.max_connected_count]u32 = undefined,

    /// Modified by the pollSockets procedure.
    conns_should_read: [constants.max_connected_count]bool = undefined,

    /// Used to know when to set conns_owned_players as only the latest input packets
    /// should affect conns_owned_players.
    conns_latest_input_from_client: [constants.max_connected_count]u64 = undefined,

    /// What player does the server thing a certain client is trying to control.
    /// This affects disconnect logic as well as the is_owned flag when sending the timeline.
    conns_owned_players: [constants.max_connected_count]input.PlayerBitSet = undefined,

    /// Parsed packages that are ready to be ingested by the InputMerger.
    incoming_packets: [constants.max_connected_count * max_input_packets_per_socket]NetworkingQueue.Packet = undefined,

    /// How many packets are in the incoming_packets queue.
    incoming_packets_count: u64 = 0,

    fn connectSlot(self: *NetServerData) ?usize {
        for (self.conns_type, 0..) |t, i| {
            if (t != .empty) {
                continue;
            }
            self.conns_type[i] = .remote;
            self.conns_list[i] = .{};
            self.conns_should_read[i] = false;
            self.conns_packet_buffer[i] = .{};
            self.conns_latest_input_from_client[i] = 0;
            self.conns_max_packets_per_send[i] = 8;
            self.conns_owned_players[i] = input.empty_player_bit_set;
            return i;
        }
        return null;
    }

    fn ingestPlayerInput(self: *NetServerData, change: NetworkingQueue.Packet) !void {
        var players = change.players.iterator(.{});

        var did_set = false;
        while (players.next()) |player| {
            did_set = did_set or try self.input_merger.remoteUpdate(std.heap.page_allocator, @truncate(player), change.data[player], change.tick);
        }

        if (!did_set) {
            // If input was already set, we can just exit early and not resend anything.
            return;
        }

        inline for (&self.conns_list, self.conns_type) |*connection, conn_type| {
            if (conn_type != .empty) {
                connection.consistent_until = @min(connection.consistent_until, change.tick);
            }
        }
    }
};

fn parsePacketFromClient(client_index: usize, server_data: *NetServerData, packet: []const u8) !void {
    if (packet.len == 0) {
        return;
    }

    //debugPacket(packet);

    var client = &server_data.conns_list[client_index];
    var scanner = cbor.Scanner{};
    var ctx = scanner.begin(packet);
    var input_synch = try ctx.readArray();
    std.debug.assert(input_synch.items == 3);
    client.tick_acknowledged = @max(client.tick_acknowledged, try input_synch.readU64());
    server_data.conns_max_packets_per_send[client_index] = @truncate(try input_synch.readU64());
    //std.debug.print("packet from client with tick ack {}\n", .{new_tick_acknowledged});
    var all_packets = try input_synch.readArray();

    for (0..all_packets.items) |_| {
        var tick_info = try all_packets.readArray();
        std.debug.assert(tick_info.items == 2);
        const input_tick_index = try tick_info.readU64();

        var all_inputs = try tick_info.readArray();

        var players_affected = input.empty_player_bit_set;
        var player_buttons = input.default_input_state;

        if (input_tick_index == 0) {
            std.debug.panic("server tried to change player input states for tick 0", .{});
        }

        for (0..all_inputs.items) |_| {
            var player_input = try all_inputs.readArray();
            std.debug.assert(player_input.items == 4);
            const player_index = try player_input.readU64();
            const dpad = try player_input.readU64();
            const button_a = try player_input.readU64();
            const button_b = try player_input.readU64();

            if (player_index >= constants.max_player_count) {
                std.debug.panic("client seems to support more players than client does", .{});
            }

            player_buttons[player_index] = .{
                .dpad = @enumFromInt(dpad),
                .button_a = @enumFromInt(button_a),
                .button_b = @enumFromInt(button_b),
            };

            players_affected.set(player_index);

            try player_input.readEnd();
        }

        try all_inputs.readEnd();
        try tick_info.readEnd();

        if (server_data.incoming_packets_count >= server_data.incoming_packets.len) {
            // TODO: Maybe we could ask the client for a resend here?
            std.debug.panic("desynch caused by too many packets from player\n", .{});
        }

        server_data.incoming_packets[server_data.incoming_packets_count] = .{
            .tick = @truncate(input_tick_index),
            .data = player_buttons,
            .players = players_affected,
        };
        server_data.incoming_packets_count += 1;

        if (server_data.conns_latest_input_from_client[client_index] < input_tick_index) {
            // The most recent tick from the client dictates what players it has
            // control over.
            server_data.conns_latest_input_from_client[client_index] = input_tick_index;
            server_data.conns_owned_players[client_index] = players_affected;
            //std.debug.print("setting ownership mask {b}\n", .{server_data.conns_owned_players[client_index].mask});
        }
    }
    try all_packets.readEnd();
    try input_synch.readEnd();
}

fn clientConnected(server_data: *NetServerData, conn: std.net.Server.Connection) void {
    std.debug.print("incoming player\n", .{});

    if (server_data.connectSlot()) |slot| {
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

        if (networking_queue.outgoing_data_count >= networking_queue.outgoing_data.len) {
            std.debug.print("a local client is having trouble keeping up with server\n", .{});
            return new_consistent_until;
        }

        //std.debug.print("sending to local an update for player 0b{b} at tick {d}\n", .{is_certain.mask, tick_index});
        networking_queue.outgoing_data[networking_queue.outgoing_data_count] = .{
            .tick = tick_index,
            .players = is_certain,
            .data = inputs,
        };
        networking_queue.outgoing_data_count += 1;

        // TODO: Doing + 1 here probably causes a desynch.
        new_consistent_until = @max(new_consistent_until, tick_index + 1);
    }
    return new_consistent_until;
}

fn sendUpdatesToRemoteClient(fd: std.posix.socket_t, input_merger: *InputMerger, consistent_until: u64, targeted_tick: u64, is_owned: input.PlayerBitSet) !u64 {
    var send_buffer: [max_net_packet_size]u8 = undefined;
    const send_amount = targeted_tick - consistent_until;

    var fb = std.io.fixedBufferStream(send_buffer[4..]);
    const writer = fb.writer();
    try cbor.writeArrayHeader(writer, 2);
    try cbor.writeUint(writer, input_merger.buttons.items.len); // Tell the client how long the complete timeline is.
    try cbor.writeArrayHeader(writer, send_amount);
    for (consistent_until..targeted_tick) |tick_index| {
        const inputs = input_merger.buttons.items[tick_index];
        const is_certain = input_merger.is_certain.items[tick_index];

        try cbor.writeArrayHeader(writer, 2);
        try cbor.writeUint(writer, tick_index);
        try cbor.writeArrayHeader(writer, is_certain.count());
        for (0..constants.max_player_count) |player| {
            if (!is_certain.isSet(player)) {
                // No point in sending something that we are unsure of.
                continue;
            }
            const player_input = inputs[player];
            try cbor.writeArrayHeader(writer, 5);
            try cbor.writeUint(writer, if (is_owned.isSet(player)) 1 else 0);
            try cbor.writeUint(writer, player);
            try cbor.writeUint(writer, @intFromEnum(player_input.dpad));
            try cbor.writeUint(writer, @intFromEnum(player_input.button_a));
            try cbor.writeUint(writer, @intFromEnum(player_input.button_b));
        }
    }

    //std.debug.print("sending packet of length {d}\n", .{fb.pos});

    // There is an explanation for this line in this file. Just search for writeInt.
    std.mem.writeInt(std.math.ByteAlignedInt(u32), send_buffer[0..4], @truncate(fb.pos), std.builtin.Endian.little);

    _ = std.posix.send(fd, send_buffer[0 .. fb.pos + 4], 0) catch |e| switch (e) {
        error.WouldBlock => 0,
        else => return e,
    };
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

    for (server_data.incoming_packets[0..server_data.incoming_packets_count]) |packet| {
        try server_data.ingestPlayerInput(packet);
    }
    server_data.incoming_packets_count = 0;

    // Send the updates to the clients.
    for (&server_data.conns_list, server_data.conns_type, &server_data.conns_sockets, server_data.conns_owned_players, server_data.conns_max_packets_per_send) |*connection, conn_type, fd, is_owned, packet_count_bandwidth| {

        // Send the missing inputs. But only N at the time.
        const send_start = connection.consistent_until;

        const send_until = @min(server_data.input_merger.buttons.items.len, send_start + packet_count_bandwidth);

        if (send_until <= send_start) {
            // Nothing to send.
            continue;
        }

        if (conn_type == .empty) {
            continue;
        }

        if (connection.tick_acknowledged + max_unresponded_ticks < connection.consistent_until) {
            // We have sent too much without a response, time to wait for a response.
            //std.debug.print("tick ack {} and consistent until {}\n", .{connection.tick_acknowledged, connection.consistent_until});
            continue;
        }

        //std.debug.print("sending {any} {d} to {d} with packet bandwith {d}\n", .{conn_type, send_start, send_until, packet_count_bandwidth});

        connection.consistent_until = switch (conn_type) {
            .local => sendUpdatesToLocalClient(networking_queue, &server_data.input_merger, send_start, send_until),
            .remote => sendUpdatesToRemoteClient(fd, &server_data.input_merger, send_start, send_until, is_owned) catch |e| {
                std.debug.print("error while sending to remote client: {any}", .{e});
                continue;
            },
            .empty => 0,
        };
    }

    // Make sure the local client knows how long the complete timeline is.
    networking_queue.server_timeline_length = server_data.input_merger.buttons.items.len;

    networking_queue.rw_lock.unlock();
}

/// Sets conns_should_read[index] for any socket that has available data.
/// We also use this code in the client to poll the singular connection to the server.
/// It is nice to reuse platform-level abstraction when possible.
fn pollSockets(timeout_ms: u32, conns_type: []ConnectionType, conns_sockets: []std.posix.socket_t, conns_should_read: []bool) void {
    // TODO: Ideally, the select in pollSocket would awake from networking_queue as well, oh well!

    if (@import("builtin").os.tag == .windows) {
        var read_fd_set = std.os.windows.ws2_32.fd_set{
            .fd_array = undefined,
            .fd_count = 0,
        };

        const timeval = std.os.windows.ws2_32.timeval{
            .tv_sec = 0,
            .tv_usec = @intCast(std.time.us_per_ms * timeout_ms),
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

        const i = std.posix.poll(&poll_fds, @intCast(timeout_ms)) catch {
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

fn performDisconnect(server_data: *NetServerData, conn_index: u32) void {
    std.debug.print("disconnecting players {b}\n", .{server_data.conns_owned_players[conn_index].mask});
    const fd = server_data.conns_sockets[conn_index];
    server_data.conns_type[conn_index] = .empty;

    if (server_data.incoming_packets_count >= server_data.incoming_packets.len) {
        std.debug.panic("properly disconnecting player is impossible\n", .{});
    }
    const all_disconnected = [_]input.PlayerInputState{.{.dpad = .Disconnected}} ** constants.max_player_count;
    server_data.incoming_packets[server_data.incoming_packets_count] = .{
        .tick = server_data.input_merger.buttons.items.len,
        .data = all_disconnected,
        .players = server_data.conns_owned_players[conn_index],
    };
    server_data.incoming_packets_count += 1;
    std.posix.close(fd);
}

fn readFromSockets(server_data: *NetServerData) void {
    var packet_part_buf: [max_net_packet_size]u8 = undefined;
    pollSockets(10, &server_data.conns_type, &server_data.conns_sockets, &server_data.conns_should_read);
    for (&server_data.conns_packet_buffer, server_data.conns_sockets, server_data.conns_type, server_data.conns_should_read, 0..) |*packet_buffer, fd, conn_type, should_read, conn_index| {
        if (conn_type != .remote) {
            continue;
        }
        if (!should_read) {
            continue;
        }
        server_data.conns_should_read[conn_index] = false;

        const packet_part_len = std.posix.read(fd, &packet_part_buf) catch 0;
        if (packet_part_len == 0) {
            performDisconnect(server_data, @truncate(conn_index));
            continue;
        }
        const packet_part = packet_part_buf[0..packet_part_len];

        var full_packet = packet_buffer.toPacket(packet_part);

        //std.debug.print("reading from player {d} length {d}", .{ conn_index, length });

        // The reason that we loop here is that the client has a
        // lower clock rate for sending. If we do not handle everything
        // that we managed to read immedietly, then we will only read
        // at the clock rate of the server thread. This means
        // that eventually reads will be filled with a ton of unread
        // packets.
        while (full_packet.len > 0) {
            parsePacketFromClient(conn_index, server_data, full_packet) catch |e| {
                std.debug.print("error while parsing packet of player {d}: {any}\n", .{ conn_index, e });
            };
            full_packet = packet_buffer.toPacket("");
        }
    }
}

fn serverThread(networking_queue: *NetworkingQueue, port: u16) !void {
    var server_data = NetServerData{
        .input_merger = try InputMerger.init(std.heap.page_allocator),
    };
    //defer server_data.input_history.deinit(std.heap.page_allocator);

    if (server_data.connectSlot()) |slot| {
        // Add a local client so that the player hosting the game may also
        // interact with the game.
        server_data.conns_type[slot] = .local;
    }

    const address = try std.net.Address.parseIp("0.0.0.0", port);
    var listening = try address.listen(.{ .force_nonblocking = true });

    while (true) {
        if (listening.accept()) |new_client| {
            clientConnected(&server_data, new_client);
        } else |_| {}

        readFromSockets(&server_data);

        try serverThreadQueueTransfer(&server_data, networking_queue);

        // TODO: Debug thing. Remove later. Or refactor somehow and make it less ugly.
        const rl = @import("raylib");
        const debug_key_down = rl.isKeyDown(rl.KeyboardKey.key_p);
        if (debug_key_down and rl.isKeyPressed(rl.KeyboardKey.key_three)) {
            const file = std.io.getStdErr();
            const writer = file.writer();
            std.debug.print("server_data input_merger len {d}\n", .{server_data.input_merger.buttons.items.len});
            try server_data.input_merger.dumpInputs((server_data.input_merger.buttons.items.len >> 9) << 9, writer);
        }
    }
}

pub fn startServer(networking_queue: *NetworkingQueue, port: u16) !void {
    _ = try std.Thread.spawn(.{}, serverThread, .{networking_queue, port});
}

fn handlePacketFromServer(networking_queue: *NetworkingQueue, packet: []const u8) !u64 {
    var scanner = cbor.Scanner{};
    var ctx = scanner.begin(packet);
    var input_synch = try ctx.readArray();
    std.debug.assert(input_synch.items == 2);
    networking_queue.server_timeline_length = try input_synch.readU64();
    var all_packets = try input_synch.readArray();
    var newest_input_tick: u64 = 0;
    for (0..all_packets.items) |_| {
        var tick_info = try all_packets.readArray();
        std.debug.assert(tick_info.items == 2);
        const input_tick_index = try tick_info.readU64();
        var all_inputs = try tick_info.readArray();

        var players_affected = input.empty_player_bit_set;
        var player_buttons = input.default_input_state;

        if (input_tick_index == 0) {
            std.debug.panic("server tried to change player input states for tick 0", .{});
        }

        for (0..all_inputs.items) |_| {
            var player_input = try all_inputs.readArray();
            std.debug.assert(player_input.items == 5);
            _ = try player_input.readU64(); // TODO: is_owned is no longer used. Remove?
            const player_index = try player_input.readU64();
            const dpad = try player_input.readU64();
            const button_a = try player_input.readU64();
            const button_b = try player_input.readU64();

            if (player_index >= constants.max_player_count) {
                std.debug.panic("server seems to support more players than client does", .{});
            }

            player_buttons[player_index] = .{
                .dpad = @enumFromInt(dpad),
                .button_a = @enumFromInt(button_a),
                .button_b = @enumFromInt(button_b),
            };

            players_affected.set(player_index);

            //std.debug.print("received dpad: {any} for player {d} and tick {d}\n", .{networking_queue.outgoing_data[networking_queue.outgoing_data_count].data.dpad, player_i, input_tick_index});
            //std.debug.print("received tick {d}\n", .{input_tick_index});
            try player_input.readEnd();
        }

        try all_inputs.readEnd();
        try tick_info.readEnd();

        if (networking_queue.outgoing_data_count >= networking_queue.outgoing_data.len) {
            // It is impossible to send. So skip this iteration and all after.
            // We can't break as we want to parse the whole package.
            std.debug.print("packet from server was ignored due to networking_queue bandwith\n", .{});
            continue;
        }

        networking_queue.outgoing_data[networking_queue.outgoing_data_count] = .{
            .tick = @truncate(input_tick_index),
            .data = player_buttons,
            .players = players_affected,
        };

        networking_queue.outgoing_data_count += 1;

        // All inputs were consumed for this tick. We may now ask the server
        // to send us newer inputs. We can only set this value after we are
        // sure of all inputs being consumed.
        newest_input_tick = @max(newest_input_tick, input_tick_index);
    }
    try all_packets.readEnd();
    try input_synch.readEnd();

    return newest_input_tick;
}

const PollerForClient = struct {
    fd: [1]std.posix.socket_t,
    connection: [1]ConnectionType = .{ConnectionType.remote},
    should_read: [1]bool = .{false},
};

fn clientThread(networking_queue: *NetworkingQueue, hostname: []const u8, port: u16) !void {
    // We need the GPA because tcpConnectToHost needs to store the DNS lookups somewhere.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const stream = try std.net.tcpConnectToHost(alloc, hostname, port);
    var poller = PollerForClient{ .fd = .{stream.handle} };

    // Now that we are connected, unlock the timeline for a short moment.
    networking_queue.server_timeline_length = 0;

    std.debug.print("connection established\n", .{});
    var newest_input_tick: u64 = 0;

    // We need a packet buffer because TCP over IP is a stream protocl
    // and not a fragment protocol.
    var packet_buffer = PacketBuffer{};

    var packet_per_receive_bandwidth: u32 = 8;

    while (true) {
        var packet_part_buf: [max_net_packet_size]u8 = undefined;
        pollSockets(4, &poller.connection, &poller.fd, &poller.should_read);
        const should_read = poller.should_read[0];
        const packet_part_len = if (should_read) try stream.read(&packet_part_buf) else 0;
        const packet_part = packet_part_buf[0..packet_part_len];

        var full_packet = packet_buffer.toPacket(packet_part);

        var should_reduce_bandwidth = false;

        //debugPacket(full_packet);

        // Reset the poller. We don't care if it was ever set.
        poller.should_read[0] = false;

        networking_queue.rw_lock.lock();

        while (networking_queue.outgoing_data_count > networking_queue.outgoing_data.len / 2) {
            should_reduce_bandwidth = true;

            // If half the outgoing queue is filled, we should give the the
            // main thread some time to catch up.

            // First unlock it so that the main thread doesn't hang.
            networking_queue.rw_lock.unlock();

            // Give main thread some time...
            std.time.sleep(std.time.ns_per_ms * 2);

            std.debug.print("net sleeping to catch up\n", .{});

            // Lock it again so that the above check is safe.
            // Also makes the code following the while-loop safe.
            networking_queue.rw_lock.lock();

        }

        if (should_reduce_bandwidth) {
            packet_per_receive_bandwidth /= 2;
        } else {
            packet_per_receive_bandwidth += 4;
        }
        packet_per_receive_bandwidth = std.math.clamp(packet_per_receive_bandwidth, 1, max_packets_to_send);

        // The rational for this loop is the same as for the similiar
        // looking code found in the server thread.
        while (full_packet.len > 0) {
            const possibly_newer = try handlePacketFromServer(networking_queue, full_packet);
            newest_input_tick = @max(possibly_newer, newest_input_tick);
            full_packet = packet_buffer.toPacket("");
        }


        // We only send packets without input if we have received a packet.
        // Packets with input are always sent.
        const should_send = should_read or networking_queue.incoming_data_count > 0;

        var send_buffer: [max_net_packet_size]u8 = undefined;
        var fb = std.io.fixedBufferStream(send_buffer[4..]);
        const writer = fb.writer();

        try cbor.writeArrayHeader(writer, 3);
        try cbor.writeUint(writer, newest_input_tick);
        try cbor.writeUint(writer, packet_per_receive_bandwidth);

        //std.debug.print("client is sending {}\n", .{networking_queue.incoming_data_count});
        try cbor.writeArrayHeader(writer, networking_queue.incoming_data_count);
        for (networking_queue.incoming_data[0..networking_queue.incoming_data_count]) |packet| {
            try cbor.writeArrayHeader(writer, 2);
            try cbor.writeUint(writer, packet.tick);
            try cbor.writeArrayHeader(writer, packet.players.count());
            var players = packet.players.iterator(.{});
            while (players.next()) |player_index| {
                const data = packet.data[player_index];
                try cbor.writeArrayHeader(writer, 4);
                try cbor.writeUint(writer, player_index);
                try cbor.writeUint(writer, @intFromEnum(data.dpad));
                try cbor.writeUint(writer, @intFromEnum(data.button_a));
                try cbor.writeUint(writer, @intFromEnum(data.button_b));
            }
        }
        networking_queue.incoming_data_count = 0;

        // Patch in the length of the packet encoded as 4 bytes.
        // We use little endian because that is more common nowadays.
        // Unfortunately CBOR uses big endian, so some inconsistencies exist.
        // The reason we send the length in total bytes is that TCP over IP
        // is a stream of bytes and does not distinguish between separate
        // calls of write(). And we must know where a package ends so we can
        // start reading the next.
        std.mem.writeInt(std.math.ByteAlignedInt(u32), send_buffer[0..4], @truncate(fb.pos), std.builtin.Endian.little);

        if (should_send) {
            _ = try stream.write(send_buffer[0 .. fb.pos + 4]);
        }

        networking_queue.rw_lock.unlock();
    }
}

pub fn startClient(networking_queue: *NetworkingQueue, hostname: []const u8, port: u16) !void {
    _ = try std.Thread.spawn(.{}, clientThread, .{ networking_queue, hostname, port });
}

test "packet buffer two part" {
    var buffer = PacketBuffer{};
    try std.testing.expectEqualStrings("", buffer.toPacket(""));
    try std.testing.expectEqualStrings("", buffer.toPacket("\x01\x00\x00\x00"));
    try std.testing.expectEqualStrings("Q", buffer.toPacket("Q"));
    try std.testing.expectEqualStrings("", buffer.toPacket(""));
}

test "packet buffer directly" {
    var buffer = PacketBuffer{};
    try std.testing.expectEqualStrings("", buffer.toPacket(""));
    try std.testing.expectEqualStrings("Q", buffer.toPacket("\x01\x00\x00\x00Q"));
    try std.testing.expectEqualStrings("", buffer.toPacket(""));
}

test "packet buffer two in one" {
    var buffer = PacketBuffer{};
    try std.testing.expectEqualStrings("", buffer.toPacket(""));
    try std.testing.expectEqualStrings("Q", buffer.toPacket("\x01\x00\x00\x00Q\x01\x00\x00\x00W"));
    try std.testing.expectEqualStrings("W", buffer.toPacket("\x01\x00\x00\x00A\x01\x00\x00\x00B"));
    try std.testing.expectEqualStrings("A", buffer.toPacket(""));
    try std.testing.expectEqualStrings("B", buffer.toPacket(""));
}
