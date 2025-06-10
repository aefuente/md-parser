const std = @import("std");
const tokens = @import("tokens.zig");
const Allocator = std.mem.Allocator;

fn openOrCreateFile(file_out: []const u8) !std.fs.File {
    var cwd = std.fs.cwd();

    if (cwd.openFile(file_out, .{.mode = .write_only})) | file | {
        return file;
    } else | _ | {
        return try cwd.createFile(file_out, .{}); 
    } 

}


pub fn render(token_list: []tokens.token, file_out: []const u8) !void {
    const file = try openOrCreateFile(file_out);
    defer file.close();
    const writer = file.writer();
    
    var index: usize = 0;

    while (index < token_list.len) {
        switch (token_list[index].token_type) {
            .HEADER1, .HEADER2, .HEADER3, .HEADER4, .HEADER5, .HEADER6 => {
                if (index + 1 < token_list.len and token_list[index+1].token_type != tokens.token_type.TEXT) {
                    std.log.warn("Unable to get text for header", .{});
                    index += 1;
                }
                try std.fmt.format(writer, "<h{d}> {s} </h{d}>\n", 
                .{@intFromEnum(token_list[index].token_type)+1,
                    token_list[index+1].value.?, 
                    @intFromEnum(token_list[index].token_type)+1
                });
                index += 2;
            },
            .PARAGRAPH => {},
            .TEXT => {
                if (index > 0 and token_list[index-1].token_type != tokens.token_type.TEXT) {
                    try writer.writeAll("<p>");
                }
                try std.fmt.format(writer, "{s}\n", .{token_list[index].value.?});
                if (index + 1 < token_list.len and token_list[index + 1].token_type != tokens.token_type.TEXT) {
                    try writer.writeAll("</p>\n");
                }
            },
            .EMPTY => {

            },
            .THEMEBREAK => {

            },
            .BLOCKQUOTES => {

            },
            .FENCEDCODE => {

            },
            .INDENTCODE => {

            },
            .SETEXT1 => {

            },
            .SETEXT2 => {

            },
            .UNORDEREDLIST => {

            },
            .ORDEREDLIST => {

            },

        }
        index += 1;
    }
}
