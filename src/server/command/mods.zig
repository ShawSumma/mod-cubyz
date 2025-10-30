const std = @import("std");

const main = @import("main");
const mods = @import("../../mods.zig");
const User = main.server.User;

pub const description = "Settings for web49 modding.";
pub const usage = "/mods operation";

pub fn execute(args: []const u8, source: *User) void {
    if (std.mem.eql(u8, "reload", args)) {
        mods.reload();
    } else {
        source.sendMessage("#FF7777failed#FFFFFF: no such operation: /mod {s}", .{args});
    }
}
