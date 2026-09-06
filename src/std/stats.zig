const std = @import("std");
const revo = @import("revo");
const api = @import("api.zig");
const root = @import("root.zig");
// const pool = @import("pool.zig");

const typeof = root.typeof;
const memory = revo.memory;
const Data = memory.Data;
const VM = revo.VM;
const HostResult = root.HostResult;
const Uri = std.Uri;
const Component = std.Uri.Component;
const Table = revo.table.Table;
const testing = revo.lang.testing;

pub const impls: []const api.Impl = &.{
    .{ .name = "frequencies", .f = root.define(&.{.table}, frequencies) },
    // .{ .name = "mean", .f = root.define(&.{.table}, mean) },
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
};

/// > stats:frequencies() -> table<any>
/// returns a histogram of element frequencies as table (ele: freq)
fn frequencies(args: []const Data, vm: *VM) !HostResult {
    if (args.len != 1) return .errArity(args.len, 1);
    const table_id = args[0].asTable() orelse return .errType(0, "table", typeof(args[0], vm));
    const table = try vm.tables.get(table_id);

    const result_table_id = try vm.tables.create();
    const result = try vm.tables.get(result_table_id);

    var this_count: f64 = undefined;
    for (table.array.items) |ele| {
        if (try result.get(ele, vm)) |this_count_data| {
            this_count = this_count_data.asNum().?;
            try result.put(result_table_id, vm, ele, Data.new.num(this_count + 1));
        } else {
            try result.put(result_table_id, vm, ele, Data.new.num(1));
        }
    }

    return .data(Data.new.table(result_table_id));
}

test "stats methods" {
    try testing.topTrue("{1, 1, 1, 2, 3, 3} |> stats.frequencies() == {1=3, 2=1, 3=2}");
}

// mean(data)
// Arithmetic mean (“average”) of data.

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
