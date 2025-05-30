const std = @import("std");

pub fn myLogFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const max_scope_size = 12;
    // Ignore all non-error logging from sources other than
    // .my_project, .nice_library and the default
    const scope_prefix = "(" ++ switch (scope) {
        .md_parser, std.log.default_log_scope => @tagName(scope),
        else => if (@intFromEnum(level) <= @intFromEnum(std.log.Level.err))
            @tagName(scope)
        else
            return,
    } ++ "): ";

    const info_prefix =  "\x1b[32m[" ++ comptime level.asText() ++ "]\x1b[0m " ++ " " ** (7 - level.asText().len + (max_scope_size -  @tagName(scope).len)) ++ scope_prefix;
    const warn_prefix = "\x1b[33m[" ++ comptime level.asText() ++ "]\x1b[0m " ++ " " ** (7 - level.asText().len + (max_scope_size -  @tagName(scope).len))  ++ scope_prefix;
    const debug_prefix = "[" ++ comptime level.asText() ++ "] " ++ " " ** (7 - level.asText().len + (max_scope_size -  @tagName(scope).len))  ++ scope_prefix;
    const err_prefix = "\x1b[31m[" ++ comptime level.asText() ++ "]\x1b[0m " ++ " " ** (7 - level.asText().len + (max_scope_size -  @tagName(scope).len))  ++ scope_prefix;
    
    // Print the message to stderr, silently ignoring any errors
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    const stderr = std.io.getStdErr().writer();

    switch (level) {
        .info => {
            nosuspend stderr.print(info_prefix ++ format ++ "\n", args) catch return;
        },
        .warn => {
            nosuspend stderr.print(warn_prefix ++ format ++ "\n", args) catch return;
        },
        .debug => {
            nosuspend stderr.print(debug_prefix ++ format ++ "\n", args) catch return;
        },
        .err => {
            nosuspend stderr.print(err_prefix ++ format ++ "\n", args) catch return;
        }
    }
}
