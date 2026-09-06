const std = @import("std");
const revo = @import("../root.zig");
const root = @import("root.zig");
const api = @import("api.zig");

const Data = revo.Data;
const VM = revo.VM;
const HostResult = root.HostResult;

const csv = @import("./vendor/csv.zig");
const Reader = csv.Reader;
const Writer = csv.Writer;
const Record = csv.Record;

const Ts = root.T;

pub const Impl = struct {
    pub fn encode(vm: *VM, data: Ts.any) !HostResult {
        var buffer = std.Io.Writer.Allocating.init(vm.runtime.alloc);
        defer buffer.deinit();
        var writer = Writer.init(&buffer.writer, .{});
        try writeCsvValue(data, vm, &writer, false);

        const slice = try buffer.toOwnedSlice();
        const result = try vm.adoptDataString(slice);
        return HostResult.Ok(vm, result);
    }

    pub fn decode(vm: *VM, source: Ts.string) !HostResult {
        const str = vm.stringValue(@intFromEnum(source));
        var fixed_reader = std.Io.Reader.fixed(str);
        var reader = Reader.init(&fixed_reader, .{});

        const table_id = try vm.tables.create();

        var record = Record.init(vm.runtime.alloc);
        defer record.deinit();

        while (try reader.next(&record)) {
            const data = try recordToData(record, vm);
            const table = try vm.tables.get(table_id);
            try table.push(data);
        }

        return .data(Data.new.table(table_id));
    }
};

pub const impls = root.impls(Impl).val;

fn recordToData(record: Record, vm: *VM) anyerror!Data {
    const table_id = try vm.tables.create();
    const table = try vm.tables.get(table_id);
    for (0..record.len()) |i| {
        const field = record.get(i);
        const data = try fieldToData(field, vm);
        try table.array.append(vm.runtime.alloc, data);
    }
    return Data.new.table(table_id);
}

fn fieldToData(field: []const u8, vm: *VM) !Data {
    if (std.fmt.parseInt(i64, field, 10) catch null) |num| {
        return Data.new.num(num);
    } else if (std.fmt.parseFloat(f64, field) catch null) |float| {
        return Data.new.num(float);
    } else {
        return try vm.ownDataString(field);
    }
}

fn writeCsvValue(data: Data, vm: *VM, writer: *Writer, nested: bool) anyerror!void {
    switch (data.tag()) {
        .number => {
            try writeNum(data, vm, writer);
            if (!nested) try writer.terminateRecord();
        },
        .string => {
            try writeString(data, vm, writer);
            if (!nested) try writer.terminateRecord();
        },
        .atom => {
            const id = data.asAtom().?;
            const atom = vm.stringValue(id);
            try writer.writeField(atom);
            if (!nested) try writer.terminateRecord();
        },
        .table => {
            const table_id = data.asTable().?;
            const table = try vm.tables.get(table_id);
            for (table.array.items) |item| {
                try writeCsvValue(item, vm, writer, true);
            }
            if (nested) try writer.terminateRecord();
        },
        .tuple => {
            const tuple_id = data.asTuple().?;
            const tuple = try vm.tuples.get(tuple_id);
            for (tuple.items) |item| {
                try writeCsvValue(item, vm, writer, true);
            }
            if (nested) try writer.terminateRecord();
        },
        .struct_val => return error.UnsupportedCsvValue,
        .struct_type => return error.UnsupportedCsvValue,
        .function => return error.UnsupportedCsvValue,
        .foreign => return error.UnsupportedCsvValue,
    }
}

fn writeString(data: Data, vm: *VM, writer: *Writer) anyerror!void {
    try writer.writeField(vm.stringValue(data.asString().?));
}

fn writeNum(data: Data, vm: *VM, writer: *Writer) anyerror!void {
    const num = data.asNum().?;
    const str = try std.fmt.allocPrint(vm.runtime.alloc, "{d}", .{num});
    defer vm.runtime.alloc.free(str);
    try writer.writeField(str);
}

test "csv encode" {
    const testing = revo.lang.testing;

    try testing.topString(
        \\ csv.encode(({"a", :b, 3}, {1.2, 0.3, "1.2"}, (1,2,3))):unwrap()
    , "a,b,3\r\n1.2,0.3,1.2\r\n1,2,3\r\n");
}
