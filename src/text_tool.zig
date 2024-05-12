const std = @import("std");

const usage =
    \\Usage: ./text [options]
    \\
    \\Options:
    \\  --input-file INPUT_TXT_FILE
    \\  --output-file OUTPUT_PNG_FILE
    \\
;

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);

    var opt_input_file_path: ?[]const u8 = null;
    var opt_output_file_path: ?[]const u8 = null;

    {
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const arg = args[i];

            if (std.mem.eql(u8, "-h", arg) or std.mem.eql(u8, "--help", arg)) {
                try std.io.getStdOut().writeAll(usage);

                return std.process.cleanExit();
            } else if (std.mem.eql(u8, "--input-file", arg)) {
                i += 1;

                if (i > args.len) fatal("expected arg after '{s}'", .{arg});
                if (opt_input_file_path != null) fatal("duplicated {s} argument", .{arg});

                opt_input_file_path = args[i];
            } else if (std.mem.eql(u8, "--output-file", arg)) {
                i += 1;

                if (i > args.len) fatal("expected arg after '{s}'", .{arg});
                if (opt_output_file_path != null) fatal("duplicated {s} argument", .{arg});

                opt_output_file_path = args[i];
            } else {
                fatal("unrecognized arg: '{s}'", .{arg});
            }
        }
    }

    const input_file_path = opt_input_file_path orelse fatal("missing --input-file", .{});
    const output_file_path = opt_output_file_path orelse fatal("missing --output-file", .{});

    var input_file = std.fs.cwd().openFile(input_file_path, .{}) catch |err| {
        fatal("unable to open '{s}': {s}", .{ input_file_path, @errorName(err) });
    };
    defer input_file.close();

    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        fatal("unable to open '{s}': {s}", .{ output_file_path, @errorName(err) });
    };
    defer output_file.close();

    var reader = input_file.reader();

    const bytes = reader.readAllAlloc(arena, 512) catch |err| {
        fatal("unable to read '{s}': {s}", .{ input_file_path, @errorName(err) });
    };

    var columns: u32 = 0;
    var rows: u32 = @intFromBool(bytes.len != 0);
    var line_length: u32 = 0;

    for (bytes) |byte| {
        if (byte == '\n') {
            columns = @max(columns, line_length);
            rows += 1;
            line_length = 0;
        } else {
            line_length += 1;
            columns = @max(columns, line_length);
        }
    }

    const width = columns * 6;
    const height = rows * 8;

    const width_bytes: []const u8 = std.mem.asBytes(&width);
    const height_bytes: []const u8 = std.mem.asBytes(&height);

    // _ = width_bytes;
    // _ = height_bytes;

    const header: []const u8 = &.{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };

    const idhr_chunk: []const u8 = &.{
        // ----------------------
        0x00, 0x00, 0x00, 0x0D, // Length
        0x49, 0x48, 0x44, 0x52, // Type

        // ----- Chunk Data -----
        width_bytes[3], width_bytes[2], width_bytes[1], width_bytes[0], // Width
        height_bytes[3], height_bytes[2], height_bytes[1], height_bytes[0], // Height
        // 0x00, 0x00, 0x00, 0x01, // Width
        // 0x00, 0x00, 0x00, 0x01, // Height
        0x08, // Bit Depth
        0x00, // Color Type
        0x00, // Compression Method
        0x00, // Filter Method
        0x00, // Interlace Method

        // ----------------------
        0x90, 0x77, 0x53, 0xDE, // CRC
    };

    const idat_chunk: []const u8 = &.{
        // ----------------------
        0x00, 0x00, 0x00, 0x0C, // Length
        0x49, 0x44, 0x41, 0x54, // Type

        // ----- Chunk Data -----
        0x08, 0xD7, 0x63, 0xF8, //
        0xCF, 0xC0, 0x00, 0x00, //
        0x03, 0x01, 0x01, 0x00, //

        // ----------------------
        0x18, 0xDD, 0x8D, 0xB0, // CRC
    };

    const iend_chunk: []const u8 = &.{
        // ----------------------
        0x00, 0x00, 0x00, 0x00, // Length
        0x49, 0x45, 0x4E, 0x44, // Type

        // ----- Chunk Data -----

        // ----------------------
        0xAE, 0x42, 0x60, 0x82, // CRC
    };

    const writer = output_file.writer();

    writer.writeAll(header) catch |err| fatal("unable to write header: {s}", .{@errorName(err)});
    writer.writeAll(idhr_chunk) catch |err| fatal("unable to write idhr_chunk: {s}", .{@errorName(err)});
    writer.writeAll(idat_chunk) catch |err| fatal("unable to write idat_chunk: {s}", .{@errorName(err)});
    writer.writeAll(iend_chunk) catch |err| fatal("unable to write iend_chunk: {s}", .{@errorName(err)});

    return std.process.cleanExit();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
