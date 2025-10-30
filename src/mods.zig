const std = @import("std");

const main = @import("main");
const User = main.server.User;

const c = @cImport({
    @cInclude("interp/interp.h");
    @cInclude("opt/tee.h");
    @cInclude("opt/tree.h");
    @cInclude("io.h");
    @cInclude("read_bin.h");
});

pub const Value = union(enum) {
    none,
    
    i8: i8,
    i16: i16,
    i32: i32,
    i64: i64,

    u8: u8,
    u16: u16,
    u32: u32,
    u64: u64,

    f32: f32,
    f64: f64,

    string: []const u8,
    list: List,
    map: Map,

    const List = main.List(Value);
    const Map = std.StringHashMap(Value);

    pub fn deinit(self: Value) void {
        _ = self;
        // switch (self) {
        //     .string => {
        //         main.globalAllocator.free(self.string);
        //     },
        //     .list => {
        //         for (self.list.items) |*elem| {
        //             elem.deinit();
        //         }
        //         self.list.deinit();
        //     },
        //     .map => {
        //         var iter = self.map.iterator();
        //         while (iter.next()) |entry| {
        //             main.globalAllocator.free(entry.key_ptr.*);
        //             entry.value_ptr.deinit();
        //         }
        //         var map = self.map;
        //         map.deinit();
        //     },
        //     else => {},
        // }
    }

    // pub fn to(self: Value, T: type) !T {
    //     return switch (@typeInfo(T)) {
    //         .Int => |info| try self.toInt(T, info, v),
    //         .Float => |info| try self.toFloat(T, info, v),
    //         .Bool => |info| try self.toBool(v),
    //         .Pointer => |info| try self.toPointer(T, info, v, ally),
    //         .Array => |info| try self.toArray(T, info, v, ally),
    //         .Vector => |info| try self.toArray(T, info, v, ally),
    //         .Optional => |info| try self.toOptional(T, info, v, ally),
    //         .Struct => |info| try self.toStruct(T, info, v, ally),
    //         .Enum => |info| try self.toEnum(T, info, v),
    //         .Union => |info| try self.toUnion(T, info, v, ally),
    //         else => return error.UnsupportedType,
    //     };
    // }
 
    pub fn format(self: Value) FormatType {
        return .{ .value = self, .indent = 0 };
    }

    const FormatType = struct {
        value: Value,
        indent: usize,

        pub fn newline(self: FormatType, writer: anytype, extra: usize) !void {
            try writer.writeAll("\n");
            for (0 .. self.indent + extra) |_| {
                try writer.writeAll("    ");
            }
        }

        pub fn format(self: FormatType, writer: anytype) !void {
            const value = self.value;

            switch (value) {
                .none => try writer.writeAll("none"),

                .i8 => try writer.print("{}", .{ value.i8 }),
                .i16 => try writer.print("{}", .{ value.i16 }),
                .i32 => try writer.print("{}", .{ value.i32 }),
                .i64 => try writer.print("{}", .{ value.i64 }),

                .u8 => try writer.print("{}", .{ value.u8 }),
                .u16 => try writer.print("{}", .{ value.u16 }),
                .u32 => try writer.print("{}", .{ value.u32 }),
                .u64 => try writer.print("{}", .{ value.u64 }),

                .f32 => try writer.print("{}", .{ value.f32 }),
                .f64 => try writer.print("{}", .{ value.f64 }),

                .string => {
                    try writer.print("\"{s}\"", .{ value.string });
                },

                .list => {
                    try writer.writeAll("List {");
                    for (value.list.items) |item| {
                        try self.newline(writer, 1);
                        try writer.print("{f},", .{ FormatType{ .value = item, .indent = self.indent + 1 } });
                    }
                    try self.newline(writer, 0);
                    try writer.writeAll("}");
                },

                .map => {
                    try writer.writeAll("Map {");
                    var iter = value.map.iterator();
                    while (iter.next()) |entry| {
                        try self.newline(writer, 1);
                        try writer.print(".{s} = {f},", .{ entry.key_ptr.*, FormatType{ .value = entry.value_ptr.*, .indent = self.indent + 1 } });
                    }
                    try self.newline(writer, 0);
                    try writer.writeAll("}");
                },
            }
        }
    };
};

pub const Executor = struct {
    mod: *Mod,
    user: ?*User,
    stack: main.List(Value),

    pub fn deinit(self: *Executor) void {
        for (self.stack.items) |item| {
            item.deinit();
        }
        self.stack.deinit();
        main.stackAllocator.destroy(self);
        self.mod.latestExecutor = null;
    }

    pub fn run(self: *Executor, func: ?*c.web49_interp_block_t) void {
        _ = c.web49_interp_block_run(&self.mod.wasmInterp, @ptrCast(func));
    }

    pub fn runName(self: *Executor, name: []const u8) error{NotFound}!void {
        self.run(self.mod.get(name) orelse return error.NotFound);
    }
};

pub const Mod = struct {
    name: []const u8,
    wasmInterp: c.web49_interp_t,
    wasmModule: c.web49_module_t,
    libraries: main.List(*Library),
    latestExecutor: ?*Executor,

    pub fn init(path: []const u8) *Mod {
        var self = main.globalAllocator.create(Mod);

        const pathPointer = main.globalAllocator.dupeZ(u8, path);
        defer main.globalAllocator.free(pathPointer);

        var file = c.web49_io_input_open(pathPointer.ptr);
        defer c.web49_free(file.byte_buf);

        self.wasmModule = c.web49_readbin_module(@ptrCast(&file));
        c.web49_opt_tee_module(@ptrCast(&self.wasmModule));
        c.web49_opt_tree_module(@ptrCast(&self.wasmModule));

        self.name = main.globalAllocator.dupe(u8, path);

        self.wasmInterp = c.web49_interp_module(self.wasmModule);

        self.libraries = main.List(*Library).init(main.globalAllocator);

        self.latestExecutor = null;

        return self;
    }

    pub fn deinit(self: *Mod) void {
        for (self.libraries.items) |item| {
            var iter = item.funcs.keyIterator();
            while (iter.next()) |key| {
                main.globalAllocator.free(key.*);
            }
            item.funcs.deinit();
            main.globalAllocator.free(item.name);
            main.globalAllocator.destroy(item);
        }
        self.libraries.deinit();
        c.web49_free_interp(self.wasmInterp);
        c.web49_free_module(self.wasmModule);
        main.globalAllocator.free(self.name);
        main.globalAllocator.destroy(self);
    }

    pub fn get(self: *Mod, name: []const u8) ?*c.web49_interp_block_t {
        const exports: c.web49_section_export_t =  c.web49_module_get_section(self.wasmModule, c.WEB49_SECTION_ID_EXPORT).section.@"export";
        for (0..exports.num_entries) |i| {
            const entry = exports.entries[i];
            const entryName = std.mem.span(entry.field_str);
            if (std.mem.eql(u8, entryName, name)) {
                return &self.wasmInterp.funcs[entry.index];
            }
        }
        return null;
    }
    
    // pub fn call(self: *Mod, name: []const u8) ![]const c.web49_interp_data_t {
    //     const func = self.get(name);
    //     const returns: [*]c.web49_interp_data_t = c.web49_interp_block_run(&self.wasmInterp, @ptrCast(func));
    //     return main.globalAllocator.dupe(c.web49_interp_data_t, returns[0 .. func.nreturns]);
    // }

    pub fn executor(self: *Mod) *Executor {
        const exec: *Executor = main.globalAllocator.create(Executor);
        exec.* = .{
            .mod = self,
            .user = null,
            .stack = main.List(Value).initCapacity(main.globalAllocator, 16),
        };
        self.latestExecutor = exec;
        return exec;
    }

    pub fn makeInterpData(T: type, v: T) c.web49_interp_data_t {
        if ((T == i8) or (T == i16) or (T == i32)) {
            return .{ .i32_s = @intCast(v) };
        } else if ((T == u8) or (T == u16) or (T == u32)) {
            return .{ .i32_u = @intCast(v) };
        } else if (T == i64) {
            return .{ .i64_s = v };
        } else if (T == u64) {
            return .{ .i64_u = v };
        } else if (T == f32) {
            return .{ .@"f32" = v };
        } else if (T == f64) {
            return .{ .@"f64" = v };
        } else {
            @compileError("makeInterpData: " ++ T);
        }
    }

    pub fn getInterpData(T: type, v: c.web49_interp_data_t) T {
        if (T == i64) {
            return v.i64_s;
        } else if (T == u64) {
            return v.i64_u;
        } else if (T == f32) {
            return v.@"f32";
        } else if (T == f64) {
            return v.@"f64";
        } else if ((T == i8) or (T == i16) or (T == i32)) {
            return @intCast(v.i32_s);
        } else if ((T == u8) or (T == u16) or (T == u32)) {
            return @intCast(v.i32_u);
        } else {
            @compileError("getInterpData: " ++ T);
        }
    }

    pub fn addLibrary(self: *Mod, name: []const u8) *Library {
        const lib = main.globalAllocator.create(Library);
        lib.mod = self;
        lib.name = main.globalAllocator.dupe(u8, name);
        lib.funcs = std.StringHashMap(Function).init(main.globalAllocator.allocator);
        c.web49_interp_add_import_func(&self.wasmInterp, @ptrCast(lib), Library.lookup);
        self.libraries.append(lib);
        return lib;
    }

    pub fn addInterface(self: *Mod, name: []const u8, T: type) void {
        var lib = self.addLibrary(name);
        inline for (@typeInfo(T).@"struct".decls) | decl | {
            const func = struct {
                fn func(statePtr: ?*anyopaque, interp: c.web49_interp_t) callconv(.c) c.web49_interp_data_t {
                    const state: *Library = @ptrCast(@alignCast(statePtr orelse unreachable));

                    var args: Args = .{
                        .mod = state.mod,
                        .wasmInterp = interp,
                        .returnValue = Mod.makeInterpData(i32, 0),
                    };
                    
                    @field(T, decl.name)(&args);
                    
                    return args.returnValue;
                }
            };

            lib.define(decl.name, func.func);
        }
    }
};

const Function = ?*const fn (?*anyopaque, c.web49_interp_t) callconv(.c) c.web49_interp_data_t;

const Library = struct {
    mod: *Mod,
    name: []const u8,
    funcs: std.StringHashMap(Function),

    pub fn lookup(statePtr: ?*anyopaque, cModuleName: [*c]const u8, cFuncName: [*c]const u8) callconv(.c) [*c]c.web49_env_t {
        // const funcs = std.StringHashMap(fn([]c.web49_interp_data_t) []c.web49_interp_data_t);
        const state: *Library = @ptrCast(@alignCast(statePtr orelse unreachable));
        const moduleName = cModuleName[0 .. std.mem.len(cModuleName)];
        const funcName = cFuncName[0 .. std.mem.len(cFuncName)];
        if (!std.mem.eql(u8, moduleName, state.name)) {
            return null;
        }
        const funcPtr = state.funcs.get(funcName) orelse {
            return null;
        };
        return c.web49_env_new(@ptrCast(state), funcPtr);
    }

    pub fn define(self: *Library, name: []const u8, func: Function) void {
        self.funcs.put(main.globalAllocator.dupe(u8, name), func) catch unreachable;
    }
};

pub const Args = struct {
    mod: *Mod,
    wasmInterp: c.web49_interp_t,
    returnValue: c.web49_interp_data_t,

    pub fn ret(self: *Args, T: type, value: T) void {
        self.returnValue = Mod.makeInterpData(T, value);
    }

    pub fn executor(self: *Args) *Executor {
        return self.mod.latestExecutor.?;
    }

    pub fn user(self: *const Args) ?*User {
        return self.mod.latestExecutor.?.user;
    }

    pub fn arg(self: *const Args, T: type, index: u32) T {
        return Mod.getInterpData(T, self.wasmInterp.locals[index]);
    }

    pub fn pop(self: *const Args) Value {
        return self.mod.latestExecutor.?.stack.pop();
    }
};

const CubyzAPI = struct {
    pub fn putchar(args: *Args) void {
        const value: u8 = args.arg(u8, 0);
        std.debug.print("{c}", .{ value });
    }

    pub fn tell_user(args: *Args) void {
        const user = args.executor().user;

        var value = args.executor().stack.pop();
        defer value.deinit();

        if (user != null) {
            user.?.sendMessage("{f}", .{ value.format() });
        } else {
            std.log.info("mods tell_user: {f}", .{ value.format() });
        }
    }
};

const ObjectAPI = struct {
    pub fn get_mark(args: *Args) void {
        args.ret(i32, @intCast(args.executor().stack.items.len));
    }

    pub fn push_none(args: *Args) void {
        args.executor().stack.append(Value.none);
    }

    pub fn push_i8(args: *Args) void {
        args.executor().stack.append(.{.i8 = @intCast(args.arg(i32, 0))});
    }

    pub fn push_i16(args: *Args) void {
        args.executor().stack.append(.{.i16 = @intCast(args.arg(i32, 0))});
    }
    
    pub fn push_i32(args: *Args) void {
        args.executor().stack.append(.{.i32 = args.arg(i32, 0)});
    }
    
    pub fn push_i64(args: *Args) void {
        args.executor().stack.append(.{.i64 = args.arg(i64, 0)});
    }

    pub fn push_u8(args: *Args) void {
        args.executor().stack.append(.{.u8 = @intCast(args.arg(u32, 0))});
    }

    pub fn push_u16(args: *Args) void {
        args.executor().stack.append(.{.u16 = @intCast(args.arg(u32, 0))});
    }
    
    pub fn push_u32(args: *Args) void {
        args.executor().stack.append(.{.u32 = args.arg(u32, 0)});
    }
    
    pub fn push_u64(args: *Args) void {
        args.executor().stack.append(.{.u64 = args.arg(u64, 0)});
    }
    
    pub fn push_f32(args: *Args) void {
        args.executor().stack.append(.{.f32 = args.arg(f32, 0)});
    }
    
    pub fn push_f64(args: *Args) void {
        args.executor().stack.append(.{.f64 = args.arg(f64, 0)});
    }

    pub fn make_string(args: *Args) void {
        const start: usize = @intCast(args.arg(i32, 0));
        const end: usize = @intCast(args.arg(i32, 1));
        var string = main.List(u8).initCapacity(main.globalAllocator, end - start);
        for (start..end) |i| {
            string.append(args.executor().stack.items[i].u8);
        }
        for (start..end) |_| {
            args.executor().stack.pop().deinit();
        }
        args.executor().stack.append(.{.string = string.items});
    }

    pub fn make_list(args: *Args) void {
        const start: usize = @intCast(args.arg(i32, 0));
        const end: usize = @intCast(args.arg(i32, 1));
        var list = Value.List.initCapacity(main.globalAllocator, end - start);
        for (start..end) |i| {
            list.append(args.executor().stack.items[i]);
        }
        for (start..end) |_| {
            _ = args.executor().stack.pop();
        }
        args.executor().stack.append(.{.list = list});
    }

    pub fn make_map(args: *Args) void {
        const start: usize = @intCast(args.arg(i32, 0));
        const end: usize = @intCast(args.arg(i32, 1));
        var map = Value.Map.init(main.globalAllocator.allocator);
        
        for (0..end-start) |i| {
            if (i % 2 == 1) {
                map.put(args.executor().stack.items[start+i-1].string, args.executor().stack.items[start+i]) catch unreachable;
            }
        }

        for (0..end-start) |_| {
            _ = args.executor().stack.pop();
        }

        args.executor().stack.append(.{.map = map});
    }
};

pub var mods = main.List(*Mod).init(main.globalAllocator);

pub fn command(user: ?*User, name: []const u8) error{NotFound}!void {
    for (mods.items) |mod| {
        const funcName = std.mem.concat(main.globalAllocator.allocator, u8, &[_][]const u8{ "on_command_", name }) catch undefined;
        defer main.globalAllocator.allocator.free(funcName);
        
        const func = mod.get(funcName) orelse continue;

        var executor = mod.executor();
        defer executor.deinit();

        executor.user = user;
        executor.run(func);
        
        return;
    }

    return error.NotFound;
}

pub fn reload() void {
    while (mods.items.len != 0) {
        mods.pop().deinit();
    }
    init();
}

pub fn init() void {
    const modDir = "mods/web49";

    var dir = std.fs.cwd().openDir(modDir, .{.iterate = true}) catch return;
    defer dir.close();

    var walker = dir.walk(main.globalAllocator.allocator) catch return;
    defer walker.deinit();
    
    while (walker.next() catch null) |entry| {
        if (!std.mem.endsWith(u8, entry.path, ".wasm")) {
            continue;
        }

        const wasmPath = std.mem.concat(main.globalAllocator.allocator, u8, &[_][]const u8 {modDir, "/", entry.path}) catch return;
        defer main.globalAllocator.allocator.free(wasmPath);

        var mod = Mod.init(wasmPath);
        defer mods.append(mod);

        mod.addInterface("object", ObjectAPI);
        mod.addInterface("cubyz", CubyzAPI);

        var executor = mod.executor();
        defer executor.deinit();

        executor.runName("on_init") catch {};
    }
}

pub fn deinit() void {
    for (mods.items) |mod| {
        mod.deinit();
    }
    mods.deinit();
}

