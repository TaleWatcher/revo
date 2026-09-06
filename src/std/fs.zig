const Ts = root.T;

pub const Impl = struct {
    pub fn open(vm: *VM, path: Ts.string) !HostResult {
        const path_str = vm.stringValue(@intFromEnum(path));
        const file = if (std.fs.path.isAbsolute(path_str))
            Dir.openFileAbsolute(vm.runtime.io, path_str, .{
                .allow_directory = true,
                .path_only = true,
            }) catch |err| switch (err) {
                error.FileNotFound => return HostResult.Err(vm, "NotFound"),
                else => return HostResult.Err(vm, mapIOError(err)),
            }
        else
            Dir.cwd().openFile(vm.runtime.io, path_str, .{
                .allow_directory = true,
                .path_only = true,
            }) catch |err| switch (err) {
                error.FileNotFound => return HostResult.Err(vm, "NotFound"),
                else => return HostResult.Err(vm, mapIOError(err)),
            };
        defer file.close(vm.runtime.io);
        return HostResult.Ok(vm, try wrapFile(vm, path_str));
    }

    pub fn readdir(vm: *VM, path: Ts.string) !HostResult {
        const path_str = vm.stringValue(@intFromEnum(path));
        const open_dir = Dir.cwd().openDir(vm.runtime.io, path_str, .{
            .iterate = true,
        }) catch |err| {
            return HostResult.Err(vm, mapIOError(err));
        };
        defer open_dir.close(vm.runtime.io);
        var iter = open_dir.iterate();

        var entries = try std.ArrayList(Data).initCapacity(vm.runtime.alloc, 16);
        defer entries.deinit(vm.runtime.alloc);

        while (try iter.next(vm.runtime.io)) |ent| {
            const entry_table = try vm.tables.create();
            var t = try vm.tables.get(entry_table);
            try t.putRaw(try vm.dataAtom("name"), try vm.ownDataString(ent.name), vm);
            try t.putRaw(try vm.dataAtom("kind"), try vm.dataAtom(kindName(ent.kind)), vm);
            try entries.append(vm.runtime.alloc, Data.new.table(entry_table));
        }

        const result_table = try vm.tables.create();
        var t = try vm.tables.get(result_table);
        for (entries.items, 0..) |entry, i| {
            try t.putRaw(Data.new.num(i), entry, vm);
        }

        return HostResult.Ok(vm, Data.new.table(result_table));
    }

    pub fn @"exists?"(vm: *VM, path: Ts.string) !HostResult {
        const path_str = vm.stringValue(@intFromEnum(path));
        const file = if (std.fs.path.isAbsolute(path_str))
            Dir.openFileAbsolute(vm.runtime.io, path_str, .{
                .allow_directory = true,
                .path_only = true,
            }) catch |err| switch (err) {
                error.FileNotFound => return HostResult.Ok(vm, revo.Data.new.core(.false)),
                else => return HostResult.Err(vm, mapIOError(err)),
            }
        else
            Dir.cwd().openFile(vm.runtime.io, path_str, .{
                .allow_directory = true,
                .path_only = true,
            }) catch |err| switch (err) {
                error.FileNotFound => return HostResult.Ok(vm, revo.Data.new.core(.false)),
                else => return HostResult.Err(vm, mapIOError(err)),
            };

        defer file.close(vm.runtime.io);
        return HostResult.Ok(vm, revo.Data.new.core(.true));
    }

    pub fn remove(vm: *VM, path: Ts.string) !HostResult {
        const path_str = vm.stringValue(@intFromEnum(path));
        Dir.cwd().deleteFile(vm.runtime.io, path_str) catch |file_err| switch (file_err) {
            error.IsDir => {
                Dir.cwd().deleteDir(vm.runtime.io, path_str) catch |err| {
                    return HostResult.Err(vm, mapIOError(err));
                };
                return HostResult.Ok(vm, revo.Data.new.core(.ok));
            },
            error.FileNotFound => return HostResult.Err(vm, "NotFound"),
            else => return HostResult.Err(vm, mapIOError(file_err)),
        };

        return HostResult.Ok(vm, revo.Data.new.core(.ok));
    }

    pub fn rename(vm: *VM, old_path: Ts.string, new_path: Ts.string) !HostResult {
        const old = vm.stringValue(@intFromEnum(old_path));
        const new = vm.stringValue(@intFromEnum(new_path));
        Dir.cwd().rename(old, Dir.cwd(), new, vm.runtime.io) catch |err| {
            return HostResult.Err(vm, mapIOError(err));
        };

        return HostResult.Ok(vm, revo.Data.new.core(.ok));
    }

    pub fn read(vm: *VM, self: Ts.table) !HostResult {
        const handle = parseFileHandle(Data.new.table(@intFromEnum(self)), vm) catch return HostResult.Err(vm, "InvalidFile");

        const st = Dir.cwd().statFile(vm.runtime.io, handle.path, .{}) catch return HostResult.Err(vm, "StatError");
        if (st.size > max_read_size) return HostResult.Err(vm, "FileTooLarge");

        const data = Dir.cwd().readFileAlloc(
            vm.runtime.io,
            handle.path,
            vm.runtime.alloc,
            .limited(max_read_size),
        ) catch |err| {
            return HostResult.Err(vm, mapIOError(err));
        };

        return HostResult.Ok(vm, try vm.adoptDataString(data));
    }

    pub fn stat(vm: *VM, self: Ts.table) !HostResult {
        const handle = parseFileHandle(Data.new.table(@intFromEnum(self)), vm) catch return HostResult.Err(vm, "InvalidFile");
        const st = Dir.cwd().statFile(vm.runtime.io, handle.path, .{}) catch |err| {
            return HostResult.Err(vm, mapIOError(err));
        };

        return HostResult.Ok(vm, try makeStatTable(vm, st));
    }

    pub fn lstat(vm: *VM, self: Ts.table) !HostResult {
        const handle = parseFileHandle(Data.new.table(@intFromEnum(self)), vm) catch return HostResult.Err(vm, "InvalidFile");
        const st = Dir.cwd().statFile(vm.runtime.io, handle.path, .{ .follow_symlinks = false }) catch |err| {
            return HostResult.Err(vm, mapIOError(err));
        };

        return HostResult.Ok(vm, try makeStatTable(vm, st));
    }

    pub fn close(vm: *VM, self: Ts.table) !HostResult {
        _ = parseFileHandle(Data.new.table(@intFromEnum(self)), vm) catch return HostResult.Err(vm, "InvalidFile");
        return HostResult.Ok(vm, revo.Data.new.core(.ok));
    }
};

pub const impls: []const api.Impl = if (@import("build_options").is_freestanding)
    &[_]api.Impl{}
else
    root.impls(Impl).val ++ &[_]api.Impl{
        // file.readdir; same name as fs.readdir, k=1
        .{ .name = "readdir", .f = root.def(fileReaddirImpl) },
        // variadic functions
        .{ .name = "mkdir", .f = root.defineVariadic(&.{.string}, mkdir_fn) },
        .{ .name = "write", .f = root.defineVariadic(&.{ .any, .any }, write_fn) },
        .{ .name = "append", .f = root.defineVariadic(&.{ .any, .any }, append_fn) },
    };

fn fileReaddirImpl(vm: *VM, self: Ts.table) !HostResult {
    const handle = parseFileHandle(Data.new.table(@intFromEnum(self)), vm) catch return HostResult.Err(vm, "InvalidFile");
    const path = handle.path;

    const open_dir = Dir.cwd().openDir(vm.runtime.io, path, .{
        .iterate = true,
    }) catch |err| {
        return HostResult.Err(vm, mapIOError(err));
    };
    defer open_dir.close(vm.runtime.io);
    var iter = open_dir.iterate();

    var entries = try std.ArrayList(Data).initCapacity(vm.runtime.alloc, 16);
    defer entries.deinit(vm.runtime.alloc);

    while (try iter.next(vm.runtime.io)) |ent| {
        const entry_table = try vm.tables.create();
        var t = try vm.tables.get(entry_table);
        try t.putRaw(try vm.dataAtom("name"), try vm.ownDataString(ent.name), vm);
        try t.putRaw(try vm.dataAtom("kind"), try vm.dataAtom(kindName(ent.kind)), vm);
        try entries.append(vm.runtime.alloc, Data.new.table(entry_table));
    }

    const result_table = try vm.tables.create();
    var t = try vm.tables.get(result_table);
    for (entries.items, 0..) |entry, i| {
        try t.putRaw(Data.new.num(i), entry, vm);
    }

    return HostResult.Ok(vm, Data.new.table(result_table));
}

fn mkdir_fn(args: []const Data, vm: *VM) !HostResult {
    const path = vm.stringValue(args[0].asString().?);
    const permissions: File.Permissions = if (args.len > 1)
        parsePermissions(vm, args[1]) catch return HostResult.Err(vm, "InvalidPermissions")
    else if (builtin.target.os.tag == .windows)
        @as(File.Permissions, @enumFromInt(0))
    else
        .default_dir;

    Dir.cwd().createDir(vm.runtime.io, path, permissions) catch |err| {
        return HostResult.Err(vm, mapIOError(err));
    };
    return HostResult.Ok(vm, revo.Data.new.core(.ok));
}

fn write_fn(args: []const Data, vm: *VM) !HostResult {
    const handle = parseFileHandle(args[0], vm) catch return HostResult.Err(vm, "InvalidFile");
    if (!args[1].isString()) return HostResult.Err(vm, "InvalidArguments");
    const permissions = if (args.len > 2) parsePermissions(vm, args[2]) catch return HostResult.Err(vm, "InvalidPermissions") else .default_file;

    const data = vm.stringValue(args[1].asString().?);
    Dir.cwd().writeFile(vm.runtime.io, .{
        .sub_path = handle.path,
        .data = data,
        .flags = .{ .permissions = permissions },
    }) catch |err| {
        return HostResult.Err(vm, mapIOError(err));
    };

    return HostResult.Ok(vm, Data.new.num(data.len));
}

fn append_fn(args: []const Data, vm: *VM) !HostResult {
    const handle = parseFileHandle(args[0], vm) catch return HostResult.Err(vm, "InvalidFile");
    if (!args[1].isString()) return HostResult.Err(vm, "InvalidArguments");
    const permissions = if (args.len > 2) parsePermissions(vm, args[2]) catch return HostResult.Err(vm, "InvalidPermissions") else .default_file;

    const data = vm.stringValue(args[1].asString().?);
    const file = Dir.cwd().openFile(vm.runtime.io, handle.path, .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => Dir.cwd().createFile(vm.runtime.io, handle.path, .{
            .truncate = false,
            .permissions = permissions,
        }) catch |e| return HostResult.Err(vm, mapIOError(e)),
        else => return HostResult.Err(vm, mapIOError(err)),
    };
    defer file.close(vm.runtime.io);

    const stat = file.stat(vm.runtime.io) catch |err| {
        return HostResult.Err(vm, mapIOError(err));
    };
    try file.writePositionalAll(vm.runtime.io, data, stat.size);

    return HostResult.Ok(vm, Data.new.num(data.len));
}

// -- internal helpers (unchanged) --

const path_key = "__path";
pub const max_read_size = 1024 * 1024 * 1024;
const PermTag = @typeInfo(File.Permissions).@"enum".tag_type;

const FileHandle = struct {
    path: []const u8,
};

fn wrapFile(vm: *VM, path: []const u8) !Data {
    const file_table = try vm.tables.create();
    var table = try vm.tables.get(file_table);
    try table.putRaw(try vm.dataAtom(path_key), try vm.ownDataString(path), vm);

    const metatable = try vm.tables.create();
    var mt = try vm.tables.get(metatable);
    const file_module = vm.globals.get(revo.core_atoms.file.atomId()) orelse return error.FileModuleNotFound;
    try mt.putRaw(try vm.dataAtom("__index"), file_module, vm);

    const set_result = try meta.set_meta(&.{ Data.new.table(file_table), Data.new.table(metatable) }, vm);
    if (set_result != .ok) return error.SetMetatableFailed;
    return Data.new.table(file_table);
}

fn parseFileHandle(value: Data, vm: *VM) !FileHandle {
    if (!value.isTable()) return error.InvalidFile;
    const table = try vm.tables.get(value.asTable().?);

    const path_data = table.getRaw(try vm.dataAtom(path_key), vm) orelse return error.InvalidFile;

    return .{
        .path = if (path_data.asString()) |id| vm.stringValue(id) else return error.InvalidFile,
    };
}

fn kindName(kind: File.Kind) []const u8 {
    return switch (kind) {
        .file => "file",
        .directory => "directory",
        .sym_link => "symlink",
        else => "unknown",
    };
}

fn parsePermissions(vm: *VM, value: Data) !File.Permissions {
    switch (value.tag()) {
        .number => {
            const n = value.asNum().?;
            if (!std.math.isFinite(n) or @floor(n) != n) return error.InvalidPermissions;
            const raw: PermTag = @intFromFloat(n);
            return @as(File.Permissions, @enumFromInt(raw));
        },
        .atom => {
            const id = value.asAtom().?;
            const name = vm.stringValue(id);
            inline for (@typeInfo(File.Permissions).@"enum".fields) |field| {
                if (std.mem.eql(u8, field.name, name)) {
                    return @as(File.Permissions, @enumFromInt(field.value));
                }
            }
            return error.InvalidPermissions;
        },
        else => return error.InvalidPermissions,
    }
}

fn makeStatTable(vm: *VM, stat: File.Stat) !Data {
    const table = try vm.tables.create();
    var t = try vm.tables.get(table);

    try t.putRaw(try vm.dataAtom("size"), Data.new.num(stat.size), vm);
    try t.putRaw(try vm.dataAtom("kind"), try vm.dataAtom(@tagName(stat.kind)), vm);
    try t.putRaw(try vm.dataAtom("permissions"), Data.new.num(@intFromEnum(stat.permissions)), vm);
    try t.putRaw(try vm.dataAtom("mtime"), Data.new.num(stat.mtime.toSeconds()), vm);
    try t.putRaw(try vm.dataAtom("atime"), Data.new.num((stat.atime orelse stat.mtime).toSeconds()), vm);
    try t.putRaw(try vm.dataAtom("ctime"), Data.new.num(stat.ctime.toSeconds()), vm);

    return Data.new.table(table);
}

pub fn mapIOError(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => "NotFound",
        error.AccessDenied => "PermissionDenied",
        error.PermissionDenied => "PermissionDenied",
        error.IsDir => "IsDirectory",
        error.NotDir => "NotDirectory",
        error.PathAlreadyExists => "AlreadyExists",
        error.ReadOnlyFileSystem => "ReadOnlyFileSystem",
        error.NoSpaceLeft => "NoSpaceLeft",
        error.FileBusy => "FileBusy",
        error.DeviceBusy => "DeviceBusy",
        error.WouldBlock => "WouldBlock",
        error.Unexpected => "IoError",
        else => "UnknownError",
    };
}

fn sourceForPath(comptime template: []const u8, path: []const u8) ![]u8 {
    return std.fmt.allocPrint(alloc, template, .{path});
}

test "fs.open/read reads file contents" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "a.txt", .data = "hello from fs" });

    const dir_path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(dir_path);
    const file_path = try std.fs.path.join(alloc, &.{ dir_path, "a.txt" });
    defer alloc.free(file_path);

    const source = try sourceForPath(
        \\ fs.open('{s}'):unwrap():read():unwrap()
    , file_path);
    defer alloc.free(source);

    try testing.topString(source, "hello from fs");
}

test "fs.write overwrites file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "w.txt", .data = "old" });

    const dir_path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(dir_path);
    const file_path = try std.fs.path.join(alloc, &.{ dir_path, "w.txt" });
    defer alloc.free(file_path);

    const source = try sourceForPath(
        \\ const f = fs.open('{s}'):unwrap()
        \\ f:write("new value"):unwrap()
        \\ f:read():unwrap()
    , file_path);
    defer alloc.free(source);

    try testing.topString(source, "new value");
}

test "fs.append appends to file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "app.txt", .data = "hello" });

    const dir_path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(dir_path);
    const file_path = try std.fs.path.join(alloc, &.{ dir_path, "app.txt" });
    defer alloc.free(file_path);

    const source = try sourceForPath(
        \\ const f = fs.open('{s}'):unwrap()
        \\ f:append(" world"):unwrap()
        \\ f:read():unwrap()
    , file_path);
    defer alloc.free(source);

    try testing.topString(source, "hello world");
}

test "fs.readdir returns table of entries" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "a.txt", .data = "a" });
    try tmp.dir.writeFile(io, .{ .sub_path = "b.txt", .data = "b" });

    const dir_path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(dir_path);

    const source = try sourceForPath(
        \\ type(fs.readdir('{s}'):unwrap()) == :table
    , dir_path);
    defer alloc.free(source);
    try testing.topTrue(source);
}

test "fs.readdir returns entries with name and kind" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "x.txt", .data = "hello" });
    try tmp.dir.writeFile(io, .{ .sub_path = "y.txt", .data = "world" });

    const dir_path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(dir_path);

    const source = try sourceForPath(
        \\ const entries = fs.readdir('{s}'):unwrap()
        \\ const e1 = entries[1]
        \\ e1.name != :nil and e1.kind != :nil
    , dir_path);
    defer alloc.free(source);
    try testing.topTrue(source);
}

test "fs.dir:readdir() returns entries" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "z.txt", .data = "test" });

    const dir_path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(dir_path);

    const source = try sourceForPath(
        \\ const dir = fs.open('{s}'):unwrap()
        \\ const entries = dir:readdir():unwrap()
        \\ type(entries) == :table
    , dir_path);
    defer alloc.free(source);
    try testing.topTrue(source);
}

test "fs.readdir works with current directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "c.txt", .data = "data" });

    const dir_path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(dir_path);

    const source = try sourceForPath(
        \\ const entries = fs.readdir('{s}'):unwrap()
        \\ type(entries) == :table
    , dir_path);
    defer alloc.free(source);
    try testing.topTrue(source);
}

const std = @import("std");
const Dir = std.Io.Dir;
const File = std.Io.File;
const io = std.testing.io;
const alloc = std.testing.allocator;
const builtin = @import("builtin");

const revo = @import("../root.zig");
const Data = revo.Data;
const VM = revo.VM;
const testing = revo.lang.testing;
const api = @import("api.zig");
const meta = @import("meta.zig");
const root = @import("root.zig");
const HostResult = root.HostResult;
