const std = @import("std");
const revo = @import("revo");
const api = @import("api.zig");
const root = @import("root.zig");
const table_std = @import("table.zig");
// const pool = @import("pool.zig");
const Ts = root.T;

const typeof = root.typeof;
const memory = revo.memory;
const Data = memory.Data;
const VM = revo.VM;
const HostResult = root.HostResult;
const Uri = std.Uri;
const Component = std.Uri.Component;
const Table = revo.table.Table;
const testing = revo.lang.testing;
const table_methods = table_std.Impl;

pub const Impl = struct {
    /// > stats:frequencies() -> table<any>
    /// returns a histogram of element frequencies as table (ele: freq)
    pub fn frequencies(vm: *VM, table_id: Ts.table) !HostResult {
        const table = try vm.tables.get(@intFromEnum(table_id));

        const result_table_id = try vm.tables.create();
        const result = try vm.tables.get(result_table_id);

        for (table.array.items) |ele| {
            if (try result.get(ele, vm)) |this_count_data| {
                try result.put(result_table_id, vm, ele, Data.new.num(this_count_data.asNum().? + 1));
            } else {
                try result.put(result_table_id, vm, ele, Data.new.num(1));
            }
        }

        return .data(Data.new.table(result_table_id));
    }

    // stats:mean() -> num
    // Arithmetic mean (“average”) of data.
    pub fn mean(vm: *VM, table_id: Ts.table) !HostResult {
        const table = try vm.tables.get(@intFromEnum(table_id));

        var sum: f64 = 0.0;
        for (table.array.items) |ele| {
            sum += ele.asNum().?;
        }

        return .data(Data.new.num(sum / @as(f64, @floatFromInt(table.array.items.len))));
    }

    // stats:median() -> num
    // Middle value of input data.
    pub fn median(vm: *VM, table_id: Ts.table) !HostResult {
        const sorted_table_id = try table_methods.copy(vm, table_id);
        const sorted_table = (try vm.tables.get(@intFromEnum(sorted_table_id))).*;
        try table_methods.sort(vm, sorted_table_id);
        const n: usize = sorted_table.array.items.len;

        if (n == 0) {
            return .errType(0, "table with at least 1 element", "no median for empty data");
        } else if (n % 2 == 1) {
            const middle_ele = sorted_table.array.items[n / 2];
            return .data(Data.new.num(middle_ele.asNum().?));
        } else {
            const i: usize = n / 2;
            return .data(Data.new.num((sorted_table.array.items[i - 1].asNum().? + sorted_table.array.items[i].asNum().?) / 2));
        }
    }
};

pub const impls: []const api.Impl = root.impls(Impl).val;
// ++ &.{
// .{ .name = "fmean", .f = root.define(&.{ .table }, fmean) },
// .{ .name = "geometric_mean", .f = root.define(&.{ .table }, geometric_mean) },
// .{ .name = "harmonic_mean", .f = root.defineVariadic(&.{.table}, harmonic_mean) },
// .{ .name = "median", .f = root.define(&.{.table}, median) },
// .{ .name = "median_low", .f = root.define(&.{ .table }, median_low) },
// .{ .name = "median_high", .f = root.define(&.{ .table }, median_high) },
// .{ .name = "median_grouped", .f = root.define(&.{.table}, median_grouped) },
// .{ .name = "mode", .f = root.define(&.{.table}, mode) },
// .{ .name = "multimode", .f = root.define(&.{ .table }, multimode) },
// .{ .name = "quantiles", .f = root.define(&.{.table}, quantiles) },
// .{ .name = "stdev", .f = root.define(&.{ .table }, stdev) },
// .{ .name = "variance", .f = root.define(&.{.table}, variance) },
// .{ .name = "covariance", .f = root.define(&.{ .table }, covariance) },
// .{ .name = "correlation", .f = root.define(&.{.table}, correlation) },
// .{ .name = "linear_regression", .f = root.define(&.{.table}, linear_regression) },
// };

test "stats methods" {
    try testing.topTrue("{1, 1, 1, 2, 3, 3} |> stats.frequencies() == {1=3, 2=1, 3=2}");
    try testing.topTrue("{1, 1, 1, 2, 3} |> stats.mean() == 1.6");
    try testing.topTrue("{3, 1, 2, 1, 1} |> stats.median() == 1");
    try testing.topTrue("{3, 1, 2, 1, 3, 1} |> stats.median() == 1.5");
}


// fmean(data, weights=None)
// Fast, floating-point arithmetic mean, with optional weighting.

// geometric_mean(data)
// Geometric mean of data.

// harmonic_mean(data, weights=None)
// Harmonic mean of data.

// median(data)
// Median (middle value) of data.

// median_low(data)
// Low median of data.

// median_high(data)
// High median of data.

// median_grouped(data, interval=1.0)
// Median (50th percentile) of grouped data.

// mode(data)
// Single mode (most common value) of discrete or nominal data.

// multimode(data)
// List of modes (most common values) of discrete or nominal data.

// quantiles(data, n=4, method='exclusive')
// Divide data into intervals with equal probability.

// stdev(data, xbar=None)
// Sample standard deviation of data.

// variance(data, xbar=None)
// Sample variance of data.

// covariance(x, y)
// Sample covariance for two variables.

// correlation(x, y, method='linear')
// Pearson and Spearman’s correlation coefficients.

// linear_regression(x, y, proportional=False)
// Slope and intercept for simple linear regression.
