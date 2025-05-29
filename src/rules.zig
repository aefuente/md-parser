//! This module holds a list of utilities and rules for the tokenization process
//! of Markdown

const std = @import("std");
const mvzr = @import("mvzr.zig");


/// Structure for holding the state to find \r\n characters
const windows_endline_normalize = enum {

    /// S for Start R for \r
    S, R
};

/// Function to replace all \r\n to just \n
pub fn normalize(data: *std.ArrayList(u8)) !void {

    // Start in the start state
    var state = windows_endline_normalize.S;

    // Initialize the search index
    var index: usize =  0;

    // Iterate through the data and replace '\r\n with \n'
    while (index < data.items.len) {
        switch (state) {
            .S => {
                if (data.items[index] == '\r') {
                    state = windows_endline_normalize.R;
                }

            },
            .R => {
                if (data.items[index] == '\n') {
                    _ = data.orderedRemove(index-1);
                    state = windows_endline_normalize.S;
                    continue;
                }
                state = windows_endline_normalize.S;
            },
        }
        index += 1;
    }
}

test "normalize line breaks" {
    const allocator = std.testing.allocator;
    const test_string1 = "This is my test string\r\nIt's\r\ngoing\rwell\n";
    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();
    try data.appendSlice(test_string1);
    try normalize(&data);
    try std.testing.expectEqualStrings(data.items, "This is my test string\nIt's\ngoing\rwell\n");

}
