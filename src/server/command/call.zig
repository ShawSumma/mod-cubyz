const std = @import("std");

const main = @import("main");
const mods = @import("../../mods.zig");
const User = main.server.User;

pub const description = "Call function from a Web49 modding.";
pub const usage = "/call func";

pub fn execute(args: []const u8, source: *User) void {
    mods.command(source, args) catch {
        source.sendMessage("#FF7777failed#FFFFFF: /mod {s}", .{args});
    };
}
