// TODO: Still heavily a work in progress.
// TODO: Handle disconnects (clear a slot)
// TODO: Parse packets and send packets
// TODO: Keep track of old state and request resimulation

const std = @import("std");
const constants = @import("constants.zig");
const xev = @import("xev");

const NetData = struct {
    // Any common data.
    // No clue if even needed.
};

const ConnectedClient = struct {
    server_data: *NetServerData,
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
        for(self.slot_occupied, 0..) |occupied, i| {
            if (!occupied) {
                self.slot_occupied[i] = true;
                return i;
            }
        }
        return null;
    }
};

const NetClientData = struct {
    common: NetData,
};

fn writeNoop(_: ?*void, _: *xev.Loop, _: *xev.Completion, _: xev.TCP, _: xev.WriteBuffer, _: xev.WriteError!usize) xev.CallbackAction {
    return .disarm;
}

fn clientMessage(client_opt: ?*ConnectedClient, l: *xev.Loop, c: *xev.Completion, s: xev.TCP, b: xev.ReadBuffer, r: xev.ReadError!usize) xev.CallbackAction {
    _ = c;
    _ = b;

    var client = client_opt orelse return .disarm;

    const packet = client.read_buffer[0..r catch return .disarm];

    std.debug.print("hi: {s}\n", .{packet});

    const write_buffer: xev.WriteBuffer = .{
        .array = .{
            .array = [2]u8{'h', 'i'} ** 16,
            .len = 2,
        }
    };
    s.write(l, &client.write_completion, write_buffer, void, null, writeNoop);

    return .rearm;
}

fn afterOverfullDisconnect(server_data_opt: ?*NetServerData, _: *xev.Loop, _: *xev.Completion, _: xev.TCP, _: xev.ShutdownError!void) xev.CallbackAction {
    const server_data = server_data_opt orelse return .disarm;
    startNewConnectionHandler(server_data);
    return .disarm;
}

fn startNewConnectionHandler(server_data: *NetServerData) void {
    server_data.listener.accept(&server_data.loop, &server_data.accept_completion, NetServerData, server_data, clientConnected);
}

fn clientConnected(server_data_opt: ?*NetServerData, l: *xev.Loop, _: *xev.Completion, r: xev.TCP.AcceptError!xev.TCP) xev.CallbackAction {
    var server_data = server_data_opt orelse return .disarm;

    var stream = r catch |e| {
        std.debug.print("e: {any}", .{e});
        return .disarm;
    };

    std.debug.print("incoming player\n", .{});

    if (server_data.reservSlot()) |slot| {
        server_data.conns_list[slot].stream = stream;
        server_data.conns_list[slot].server_data = server_data;
        const completion = &server_data.conns_list[slot].read_completion;
        const buffer = &server_data.conns_list[slot].read_buffer;
        stream.read(l, completion, .{ .slice = buffer }, ConnectedClient, &server_data.conns_list[slot], clientMessage);

        startNewConnectionHandler(server_data);
        return .disarm;
    } else {
        std.log.warn("too many players", .{});
        stream.shutdown(l, &server_data.accept_completion, NetServerData, server_data, afterOverfullDisconnect);
        return .disarm;
    }
}

fn serverThread() !void {
    var server_data = NetServerData{.loop = undefined};
    server_data.loop = try xev.Loop.init(.{ .entries = 128 });
    defer server_data.loop.deinit();

    const address = try std.net.Address.parseIp("0.0.0.0", 8080);
    server_data.listener = try xev.TCP.init(address);
    try server_data.listener.bind(address);
    try server_data.listener.listen(16);
    startNewConnectionHandler(&server_data);

    try server_data.loop.run(.until_done);
}

pub fn startServer() !void {
    _ = try std.Thread.spawn(.{}, serverThread, .{});
}

fn clientThread() !void {
    // The client doesn't currently to evented IO. I don't think it will be necessary.

    var mem: [1024]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&mem);
    const allocator = alloc.allocator();
    const stream = try std.net.tcpConnectToHost(allocator, "127.0.0.1", 8080);
    _ = try stream.write("hi");


    //std.time.sleep(std.time.ns_per_s * 1);
    while(true) {
        var packet_buf: [1024]u8 = undefined;
        std.debug.print("begin read\n", .{});
        const packet_len = try stream.read(&packet_buf);
        const packet = packet_buf[0..packet_len];
        std.debug.print("received: {s}\n", .{packet});
        _ = try stream.write("hi");
    }
}

pub fn startClient() !void {
    _ = try std.Thread.spawn(.{}, clientThread, .{});
}

