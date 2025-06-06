const std = @import("std");
const Allocator = std.mem.Allocator;
const tokens = @import("tokens.zig");
const rules = @import("rules.zig");
const mvzr = @import("mvzr.zig");


const OrderedListRegex = mvzr.Regex.compile("^[0-9]*\\.").?;
/// Returns the inclusive usize of a line
/// Example hello\n returns 6
///         012345  
/// So this can be used as data[start:usize] with \n included in the string
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

    /// Returns true or false if an ATX heading was found.
    /// Adjust the position of the parser to just after the heading
    fn headerHandler(p: *parser, data: []const u8) !bool {

        // Detects the amount of leading whitespace 
        const pre_space_count = leadingWhiteSpace(data);

        // SPEC requires whitespace less than four
        if (pre_space_count > 3) {
            return false;
        }
        var cur_pos = pre_space_count;
        
        // Next character is required to be '#' and also doing bounds checking
        if (cur_pos == data.len or data[cur_pos] != '#') {
            return false;
        }

        // Count the number of consecutive '#'
        var count: i32 = 0;
        while(cur_pos < data.len and data[cur_pos] == '#') {
            count+=1;
            cur_pos +=1;
        }

        // Spec requires six or less
        if (count > 6) {
            return false;
        }

        // Add the token to the token list
        try p.tokens.append(
            tokens.token{
                .sequence = tokens.sequence_type.CONTAINER,
                .token_type = @enumFromInt(count-1),
                .value = null
        });

        // Current pos from the previous while loop should be just after the
        // last heading
        p.pos = p.pos + cur_pos;
        return true;
    }

    /// Adds text token for a given line
    /// Sets the parser position to the next character after an end line
    fn textHandler(p: *parser, data: []const u8) !bool {

        // Check for leading whitespace
        const white_space_count = leadingWhiteSpace(data);
        
        // Spec requires less than 4 whitespaces
        if (white_space_count > 3) {
            return false;
        }
        var next_pos = data.len;
        if (data[data.len-1] == '\n') {
            next_pos = data.len - 1;
        }
        // Append the token excluding the endline
        try p.tokens.append(
            tokens.token{
            .sequence = tokens.sequence_type.LEAF,
            .token_type = tokens.token_type.TEXT,
            .value = data[white_space_count..next_pos]
        });

        // Adjust the parser position
        p.pos += data.len;

        // return true
        return true;
    }

    /// Add token for blank lines or return not found
    fn blankHandler(p: *parser, data: []const u8) !bool {

        // Check for whitespace infront
        const white_space = leadingWhiteSpace(data);

        // If the next character after whitespace isn't and endline return false
        if (white_space == data.len or data[white_space] != '\n') {
            return false;
        }

        // Add the empty token
        try p.tokens.append(
            tokens.token{
                .sequence = tokens.sequence_type.LEAF,
                .token_type = tokens.token_type.EMPTY,
                .value = null, 
            }
        );

        // Adjust the parser position
        p.pos += data.len;
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

    /// Fenced code blocks
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

        p.pos += data.len;

        return true;

    }

    fn themeBreakHandler(p: *parser, data: []const u8) !bool {
        if (data.len < 3) {
            return false;
        }

        const pre_space_count = leadingWhiteSpace(data);
        if (pre_space_count > 3) {
            return false;
        }
        var cur_pos = pre_space_count;
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
        p.pos += data.len;
        return true;

    }
    
    /// Handle setext
    pub fn setextHandler(p: *parser, data:[]const u8) !bool {
        const leading_space = leadingWhiteSpace(data);
        if (leading_space > 3) {
            return false;
        }
        var cur_pos = leading_space;

        const char = data[leading_space];

        if (char != '=' and char != '-') {
            return false;
        }
        
        while (cur_pos < data.len and data[cur_pos] != '\n') {
            if (data[cur_pos] != char) {
                return false;
            }
            cur_pos += 1;
        }

        if (char == '=') {
            try p.tokens.append(
                tokens.token{
                    .sequence = tokens.sequence_type.LEAF,
                    .token_type = tokens.token_type.SETEXT1,
                    .value = null, 
                }
            );
        }else {
            try p.tokens.append(
                tokens.token{
                    .sequence = tokens.sequence_type.LEAF,
                    .token_type = tokens.token_type.SETEXT2,
                    .value = null, 
                }
            );
        }
        p.pos += data.len;
        return true;
    }

    /// Indented code blocks need 4 white spaces
    /// The current implementation is wrong. It needs to be able to keep the
    /// whitespace but current text handler won't allow for that.
    fn indentedCodeHandler(p: *parser, data: []const u8) !bool {
        const white_space_count = leadingWhiteSpace(data);

        // Leading whitespace needs to be greater than 4
        if (white_space_count < 4) {
            return false;
        }

        // This would be blank line which is not allowed
        if (data[white_space_count] == '\n') {
            return false;
        }


        // TODO: Could allow for indent code to keep a value and parse as
        // inline?
        try p.tokens.append(
            tokens.token{
                .sequence = tokens.sequence_type.LEAF,
                .token_type = tokens.token_type.INDENTCODE,
                .value = null
            }
        );

        p.pos += white_space_count;

        return true;
    }

    fn listHandler(p: *parser, data: []const u8) !bool{
        const cur_pos = leadingWhiteSpace(data);

        const match = OrderedListRegex.match(data[cur_pos..]);
        
        if (match) | value |{
            try p.tokens.append(
                tokens.token{
                    .sequence = tokens.sequence_type.CONTAINER,
                    .token_type = tokens.token_type.ORDEREDLIST,
                    .value = data[cur_pos + value.start..value.end-1],
                }
            );
            p.pos += value.end;
            return true;
        }
        
        // Continue for - + *
        if (cur_pos + 1 < data.len and (data[cur_pos] == '-' or
            data[cur_pos] == '+' or data[cur_pos] == '*') and
            data[cur_pos + 1] == ' ')  {

            // Add the token
            try p.tokens.append(
                tokens.token{
                    .sequence = tokens.sequence_type.CONTAINER,
                    .token_type = tokens.token_type.UNORDEREDLIST,
                    .value = null,
                }
            );
            p.pos += cur_pos + 2;
            return true;
        }

        return false;

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
            if (try p.setextHandler(p.source[p.pos..line_break])) {
                continue;
            }
            if (try p.indentedCodeHandler(p.source[p.pos..line_break])){
                continue;
            }
            if (try p.listHandler(p.source[p.pos..line_break])) {
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

fn leadingWhiteSpace(data: []const u8) usize {
    var pre_space_count: usize = 0;
    for (data) | char | {
        if (char == ' ' or char == '\t') {
            pre_space_count += 1;
        }else {
            break;
        }
    }
    return pre_space_count; 
}

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
    try std.testing.expectEqual(true, try p.headerHandler(" ####Four Header"));
    try std.testing.expectEqual(true, try p.headerHandler("  ####Four Header"));
    try std.testing.expectEqual(true, try p.headerHandler("   ####Four Header"));
    try std.testing.expectEqual(false, try p.headerHandler("    ####Four Header"));
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

test "setextHandler" {
    const allocator = std.testing.allocator;
    var p = try parser.init(allocator, "dummysource");
    defer p.deinit();
    try std.testing.expectEqual(true, try p.setextHandler("---\n"));
    try std.testing.expectEqual(true, try p.setextHandler("--\n"));
    try std.testing.expectEqual(true, try p.setextHandler("-\n"));
    try std.testing.expectEqual(true, try p.setextHandler(" ---\n"));
    try std.testing.expectEqual(true, try p.setextHandler("  --\n"));
    try std.testing.expectEqual(true, try p.setextHandler("  -\n"));
    try std.testing.expectEqual(true, try p.setextHandler("===\n"));
    try std.testing.expectEqual(true, try p.setextHandler("==\n"));
    try std.testing.expectEqual(true, try p.setextHandler("=\n"));
    try std.testing.expectEqual(true, try p.setextHandler(" ===\n"));
    try std.testing.expectEqual(true, try p.setextHandler("  ==\n"));
    try std.testing.expectEqual(true, try p.setextHandler("  =\n"));
    try std.testing.expectEqual(true, try p.setextHandler("==="));
    try std.testing.expectEqual(true, try p.setextHandler("=="));
    try std.testing.expectEqual(true, try p.setextHandler("="));
    try std.testing.expectEqual(true, try p.setextHandler(" ==="));
    try std.testing.expectEqual(true, try p.setextHandler("  =="));
    try std.testing.expectEqual(true, try p.setextHandler("  ="));
    try std.testing.expectEqual(false, try p.setextHandler("    =\n"));
    try std.testing.expectEqual(false, try p.setextHandler("___"));
    try std.testing.expectEqual(false, try p.setextHandler("= ==\n"));
    try std.testing.expectEqual(false, try p.setextHandler("= == =\n"));
}

test "indentedCodeHandler" {
    const allocator = std.testing.allocator;
    var p = try parser.init(allocator, "dummysource");
    defer p.deinit();
    
    try std.testing.expectEqual(true, try p.indentedCodeHandler("    the"));
    try std.testing.expectEqual(true, try p.indentedCodeHandler("    ;"));
    try std.testing.expectEqual(true, try p.indentedCodeHandler("    the\n"));
    try std.testing.expectEqual(true, try p.indentedCodeHandler("    ;\n"));
    try std.testing.expectEqual(false, try p.indentedCodeHandler("  ;\n"));
    try std.testing.expectEqual(false, try p.indentedCodeHandler(" ;\n"));
    try std.testing.expectEqual(false, try p.indentedCodeHandler(";\n"));
}

test "listHandler" {
    const allocator = std.testing.allocator;
    var p = try parser.init(allocator, "dummysource");
    defer p.deinit();

    try std.testing.expectEqual(true, try p.listHandler("1. "));
    try std.testing.expectEqual(true, try p.listHandler("2. "));
    try std.testing.expectEqual(true, try p.listHandler("3. test more\n"));
    try std.testing.expectEqual(true, try p.listHandler("4. the rule\n"));
    try std.testing.expectEqual(true, try p.listHandler("5. "));
    try std.testing.expectEqual(true, try p.listHandler("6. "));
    try std.testing.expectEqual(true, try p.listHandler("7. "));
    try std.testing.expectEqual(true, try p.listHandler("8. "));
    try std.testing.expectEqual(true, try p.listHandler("9. "));
    try std.testing.expectEqual(true, try p.listHandler("- "));
    try std.testing.expectEqual(true, try p.listHandler("+ "));
    try std.testing.expectEqual(true, try p.listHandler("* "));
    try std.testing.expectEqual(false, try p.listHandler("-\n"));
    try std.testing.expectEqual(false, try p.listHandler("the +"));
    try std.testing.expectEqual(false, try p.listHandler("help * "));

}
