const std = @import("std");
const Allocator = std.mem.Allocator;
const tokens = @import("tokens.zig");
const rules = @import("rules.zig");
const mvzr = @import("mvzr.zig");

fn indexOfLineBreak(start: usize, data: []const u8) ?usize {
    var index = start;
    while (index < data.len) {
        if (data[index] == '\n') {
            return index;
        }
        index += 1;
    }
    return null;
}

pub const parser = struct {
    allocator: Allocator,
    source: []u8,
    tokens: std.ArrayList(tokens.token),

    pub fn init(allocator: Allocator, source: []const u8) !parser{
        var tmp_source = std.ArrayList(u8).init(allocator);
        try tmp_source.appendSlice(source);
        try rules.normalize(&tmp_source);

        return .{
            .allocator = allocator,
            .source = try tmp_source.toOwnedSlice(),
            .tokens = std.ArrayList(tokens.token).init(allocator)
        };

    }

    pub fn deinit(p: *parser) void {
        p.allocator.free(p.source);
        p.tokens.deinit();

    }

    fn headerHandler(p: *parser, data: []const u8) !?usize {
        if (data.len < 0 or data[0] != '#') {
            return null;
        }
        var count: i32 = 0;
        var cur_pos: usize = 0;
        while(cur_pos < data.len and data[cur_pos] == '#') {
            count+=1;
            cur_pos +=1;
        }
        if (count > 6) {
            return null;
        }
        try p.tokens.append(
            tokens.token{
                .sequence = tokens.sequence_type.CONTAINER,
                .token_type = @enumFromInt(count-1),
                .value = null
        });
        return cur_pos;

    }

    // Every line will produce a paragraph. Multiple Paragraphs
    // without a empty line will be translated as a single paragraph
    fn paragraphHandler(p: *parser, data: []const u8) !usize {
        var cur_pos: usize = 0;
        while (cur_pos < data.len) {
            if (data[cur_pos] == '\n') {
                try p.tokens.append(
                    tokens.token{
                    .sequence = tokens.sequence_type.INLINE,
                    .token_type = tokens.token_type.PARAGRAPH,
                    .value = data[0..cur_pos]
                });
                return cur_pos + 1;
            }
            cur_pos += 1;
        }
        try p.tokens.append(
            tokens.token{
            .sequence = tokens.sequence_type.INLINE,
            .token_type = tokens.token_type.PARAGRAPH,
            .value = data[0..cur_pos]
        });
        return cur_pos;
    }


    pub fn parse(p: *parser) ![]tokens.token {
        var cur_pos: usize = 0;
        while (indexOfLineBreak(cur_pos, p.source)) | line_break | {
            std.debug.print("line: {s}\n", .{p.source[cur_pos..line_break]});
            cur_pos = line_break + 1;
        }
        return &[_]tokens.token{};

    }
};




test "parser init" {
    const allocator = std.testing.allocator;
    const test_string =  "This is my test string\r\nIt's\r\ngoing\rwell\n";

    var p = try parser.init(allocator,test_string);
    defer p.deinit();
    try std.testing.expectEqualStrings(p.source, "This is my test string\nIt's\ngoing\rwell\n");
}

test "parser parse" {
    const allocator = std.testing.allocator;
    const test_string = "Test read\nline by line\n if thats okay\n";

    var p = try parser.init(allocator, test_string);
    defer p.deinit();
    _ = try p.parse();
}

test "headerHandler" {
    const allocator = std.testing.allocator;
    var p = try parser.init(allocator, "#Single Header");
    defer p.deinit();
    try std.testing.expectEqual(1, try p.headerHandler("#single Header"));
    try std.testing.expectEqual(2, try p.headerHandler("##DOUBLE Header"));
    try std.testing.expectEqual(4, try p.headerHandler("####Four Header"));
    
    std.debug.print("{any}\n", .{p.tokens.items});
}

test "paragraphHandler" {
    const allocator = std.testing.allocator;
    var p = try parser.init(allocator, "dummysource");
    defer p.deinit();
    try std.testing.expectEqual(11, try p.paragraphHandler("single line"));
    try std.testing.expectEqual(
        12, 
        try p.paragraphHandler("double line\n next line")
    );
    try std.testing.expectEqual(10, try p.paragraphHandler("double line\n next line"[12..]));
    for (p.tokens.items) | token| {
        std.debug.print("line: {s}\n", .{token.value.?});
    }
}
