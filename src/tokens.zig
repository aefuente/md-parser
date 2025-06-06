const std = @import("std");

pub const sequence_type = enum {
    CONTAINER,
    LEAF,
    INLINE

};

pub const token_type = enum {
    HEADER1,
    HEADER2,
    HEADER3,
    HEADER4,
    HEADER5,
    HEADER6,
    TEXT,
    PARAGRAPH,
    EMPTY,
    THEMEBREAK,
    BLOCKQUOTES,
    FENCEDCODE,
    INDENTCODE,
    SETEXT1,
    SETEXT2,
    UNORDEREDLIST,
    ORDEREDLIST,

};

pub const token = struct {
    sequence: sequence_type,
    token_type: token_type,
    value: ?[]const u8,
};


