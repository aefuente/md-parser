const std = @import("std");
const parser = @import("parser.zig");
const logging = @import("logging.zig");
const render = @import("render.zig");


pub const std_options = std.Options{
    // Set the log level to info
    .log_level = .debug,

    // Define logFn to override the std implementation
    .logFn = logging.myLogFn,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const file = try std.fs.cwd().openFile("example/test.md", .{});
    defer file.close();
    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    const data = try in_stream.readAllAlloc(allocator, 4096);
    defer allocator.free(data);

    var p = try parser.parser.init(allocator, data);
    defer p.deinit();

    _ = try p.parse();


    for (p.tokens.items) | token| {
        if (token.value) |value| {
            std.debug.print("type: {any}, value: {s}\n", .{token.token_type, value});
        } else {
            std.debug.print("type: {any}\n", .{token.token_type});
        }
    }
    try render.render(p.tokens.items, "example/output.html");
}


/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("md_parser_lib");
