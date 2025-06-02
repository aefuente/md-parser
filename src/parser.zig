const std = @import("std");
const Allocator = std.mem.Allocator;
const tokens = @import("tokens.zig");
const rules = @import("rules.zig");
const mvzr = @import("mvzr.zig");

fn indexOfLineBreak(start: usize, data: []const u8) ?usize {
    var index = start;
    while (index < data.len) {
        if (data[index] == '\n') {
            return index+1;
        }
        index += 1;
    }
    return null;
}

pub const parser = struct {
    allocator: Allocator,
    source: []u8,
    pos: usize,
    tokens: std.ArrayList(tokens.token),

    pub fn init(allocator: Allocator, source: []const u8) !parser{
        var tmp_source = std.ArrayList(u8).init(allocator);
        try tmp_source.appendSlice(source);
        try rules.normalize(&tmp_source);

        return .{
            .allocator = allocator,
            .source = try tmp_source.toOwnedSlice(),
            .pos = 0,
            .tokens = std.ArrayList(tokens.token).init(allocator)
        };

    }

    pub fn deinit(p: *parser) void {
        p.allocator.free(p.source);
        p.tokens.deinit();

    }

    fn headerHandler(p: *parser, data: []const u8) !bool {
        if (data.len == 0 or data[0] != '#') {
            return false; 
        }
        var count: i32 = 0;
        var cur_pos: usize = 0;
        while(cur_pos < data.len and data[cur_pos] == '#') {
            count+=1;
            cur_pos +=1;
        }
        if (count > 6) {
            return false;
        }
        try p.tokens.append(
            tokens.token{
                .sequence = tokens.sequence_type.CONTAINER,
                .token_type = @enumFromInt(count-1),
                .value = null
        });
        p.pos = p.pos + cur_pos;
        return true;

    }

    fn textHandler(p: *parser, data: []const u8) !bool {
        var cur_pos: usize = 0;
        while (cur_pos < data.len) {
            if (data[cur_pos] == '\n') {
                try p.tokens.append(
                    tokens.token{
                    .sequence = tokens.sequence_type.LEAF,
                    .token_type = tokens.token_type.TEXT,
                    .value = data[0..cur_pos]
                });
                p.pos = p.pos + cur_pos + 1;
                return true;
            }
            cur_pos += 1;
        }
        try p.tokens.append(
            tokens.token{
            .sequence = tokens.sequence_type.INLINE,
            .token_type = tokens.token_type.TEXT,
            .value = data[0..cur_pos]
        });
        p.pos = p.pos + cur_pos + 1;
        return true;
    }

    fn blankHandler(p: *parser, data: []const u8) !bool {

        if (data.len == 0 or data[0] != '\n') {
            return false;
        }
        try p.tokens.append(
            tokens.token{
                .sequence = tokens.sequence_type.LEAF,
                .token_type = tokens.token_type.EMPTY,
                .value = null, 
            }
        );
        p.pos += 1;
        return true;
    }

    fn blockQuotesHandler(p: *parser, data: []const u8) !bool {
        if (data.len < 2 or data[0] != '>' or data[1] == '>') {
            return false; 
        }
        try p.tokens.append(
            tokens.token{
                .sequence = tokens.sequence_type.CONTAINER,
                .token_type = tokens.token_type.BLOCKQUOTES,
                .value = null, 
            }
        );
        p.pos += 1;
        return true;
    }

    fn fencedCodeHandler(p: *parser, data: []const u8) !bool {
        var flag = false;
        if (data.len < 3) {
            return false;
        }
        if (data[0] == '`' and data[1] == '`' and data[2] == '`') {
            flag = true;
        }
        if (data[0] == '~' and data[1] == '~' and data[2] == '~') {
            flag = true;
        }

        if (!flag){ return false;}

        try p.tokens.append(
            tokens.token{
                .sequence = tokens.sequence_type.LEAF,
                .token_type = tokens.token_type.FENCEDCODE,
                .value = null, 
            }
        );
        var cur_pos: usize = 0;
        while (cur_pos < data.len and data[cur_pos] != '\n') {
            cur_pos += 1;
        }
        p.pos += cur_pos + 1;

        return true;

    }

    fn themeBreakHandler(p: *parser, data: []const u8) !bool {
        if (data.len < 3) {
            return false;
        }
        var pre_space_count: i32 = 0;
        var cur_pos: usize = 0;
        while (cur_pos < data.len and (data[cur_pos] == ' ' or data[cur_pos] == '\t')) {
            pre_space_count += 1;
            cur_pos +=1;
        }
        if (pre_space_count > 3) {
            return false;
        }
        if (data[cur_pos] != '_' and data[cur_pos] != '-' and data[cur_pos] != '*') {
            return false;
        }
        const break_char = data[cur_pos];
        var break_char_count: i32 = 0;

        while (cur_pos < data.len and data[cur_pos] != '\n') {
            if (data[cur_pos] != break_char and data[cur_pos] != ' ' and data[cur_pos] != '\t') {
                return false;
            }
            break_char_count += 1;
            cur_pos +=1;
        }


        if (break_char_count < 3) {
            return false;
        }

        try p.tokens.append(
            tokens.token{
                .sequence = tokens.sequence_type.LEAF,
                .token_type = tokens.token_type.THEMEBREAK,
                .value = null, 
            }
        );
        p.pos = p.pos + cur_pos + 1;
        return true;

    }

    pub fn parse(p: *parser) ![]tokens.token {
        while (indexOfLineBreak(p.pos, p.source)) | line_break | {
            if (try p.blankHandler(p.source[p.pos..line_break])) {
                continue;
            }
            if (try p.headerHandler(p.source[p.pos..line_break])) {
                continue;
            }
            if (try p.blockQuotesHandler(p.source[p.pos..line_break])) {
                continue;
            } 
            if (try p.fencedCodeHandler(p.source[p.pos..line_break])) {
                continue;
            }
            if (try p.themeBreakHandler(p.source[p.pos..line_break])) {
                continue;
            }
            if (try p.textHandler(p.source[p.pos..line_break])) {
                continue;
            }
            std.log.warn("Failed reading line: {s}", .{p.source[p.pos..line_break]});
            p.pos = line_break;
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
    const test_string = "#Title\n> block it\nTest\n>again\n>twice read\n\n\nline by line\n if thats okay\n";

    var p = try parser.init(allocator, test_string);
    defer p.deinit();
    _ = try p.parse();
    for (p.tokens.items) | token| {
        if (token.value) |value| {
            std.debug.print("type: {any}, value: {s}\n", .{token.token_type, value});
        } else {
            std.debug.print("type: {any}\n", .{token.token_type});
        }
    }
}

test "headerHandler" {
    const allocator = std.testing.allocator;
    var p = try parser.init(allocator, "#Single Header");
    defer p.deinit();
    try std.testing.expectEqual(true, try p.headerHandler("#single Header"));
    try std.testing.expectEqual(true, try p.headerHandler("##DOUBLE Header"));
    try std.testing.expectEqual(true, try p.headerHandler("####Four Header"));
    try std.testing.expectEqual(false, try p.headerHandler("Some #Header"));
    
    std.debug.print("{any}\n", .{p.tokens.items});
}

test "textHandler" {
    const allocator = std.testing.allocator;
    var p = try parser.init(allocator, "dummysource");
    defer p.deinit();
    try std.testing.expectEqual(true, try p.textHandler("single line"));
    try std.testing.expectEqual(
        true, 
        try p.textHandler("double line\n next line")
    );
    try std.testing.expectEqual(true, try p.textHandler("double line\n next line"[12..]));
    for (p.tokens.items) | token| {
        std.debug.print("line: {s}\n", .{token.value.?});
    }
}

test "blockQuotesHandler" {
    const allocator = std.testing.allocator;
    var p = try parser.init(allocator, "dummysource");
    defer p.deinit();
    try std.testing.expectEqual(true, try p.blockQuotesHandler("> hello\n"));
    try std.testing.expectEqual(true, try p.blockQuotesHandler(">1hello\n"));
    try std.testing.expectEqual(true, try p.blockQuotesHandler(">'hello\n"));
    try std.testing.expectEqual(true, try p.blockQuotesHandler(">'hello"));
    try std.testing.expectEqual(false, try p.blockQuotesHandler("'hello"));
    try std.testing.expectEqual(false, try p.blockQuotesHandler(">>hello"));
    try std.testing.expectEqual(false, try p.blockQuotesHandler("# >hello"));
}

test "themeBreakHandler" {
    const allocator = std.testing.allocator;
    var p = try parser.init(allocator, "dummysource");
    defer p.deinit();
    try std.testing.expectEqual(true, try p.themeBreakHandler("---\n"));
    try std.testing.expectEqual(true, try p.themeBreakHandler("***\n"));
    try std.testing.expectEqual(true, try p.themeBreakHandler("___\n"));
    try std.testing.expectEqual(true, try p.themeBreakHandler(" ***\n"));
    try std.testing.expectEqual(true, try p.themeBreakHandler("  ___\n"));
    try std.testing.expectEqual(true, try p.themeBreakHandler("   ___\n"));
    try std.testing.expectEqual(true, try p.themeBreakHandler("   ___ "));
    try std.testing.expectEqual(true, try p.themeBreakHandler("   ___   \n"));
    try std.testing.expectEqual(true, try p.themeBreakHandler("_   ___   _\n"));
    try std.testing.expectEqual(false, try p.themeBreakHandler("*_  ___   _\n"));
    try std.testing.expectEqual(false, try p.themeBreakHandler("___ some"));
}
