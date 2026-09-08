const std = @import("std");
const revo = @import("revo");
const api = @import("api.zig");
const root = @import("root.zig");
const table_std = @import("table.zig");
// const pool = @import("pool.zig");
const Ts = root.T;

const math = std.math;
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


// An accumulator for statistical data.
const RunningStat = struct {
    // amount of pushed data
    n: usize = 0,
    // self-explaining
    min: f64 = 0.0,
    max: f64 = 0.0,
    sum: f64 = 0.0,
    // statistical moments, mom1 is mean
    mom1: f64 = 0.0,
    mom2: f64 = 0.0,
    mom3: f64 = 0.0,
    mom4: f64 = 0.0,

    fn pushEle(self: *RunningStat, x: f64) void {
        // Pushes a value `x` for processing.
        if (self.n == 0) {
            self.min = x;
            self.max = x;
        } else {
            if (self.min > x)
                self.min = x;
            if (self.max < x)
                self.max = x;
        }
        self.n += 1;
        // See Knuth TAOCP vol 2, 3rd edition, page 232
        self.sum += x;
        const n_float = @as(f64, @floatFromInt(self.n));
        const delta = x - self.mom1;
        const delta_n = delta / n_float;
        const delta_n2 = delta_n * delta_n;
        const term1 = delta * delta_n * (n_float - 1);
        self.mom4 += term1 * delta_n2 * (n_float*n_float - 3*n_float + 3) + 6*delta_n2*self.mom2 - 4*delta_n*self.mom3;
        self.mom3 += term1 * delta_n * (n_float - 2) - 3*delta_n*self.mom2;
        self.mom2 += term1;
        self.mom1 += delta_n;
    }

    fn pushData(self: *RunningStat, data: *std.ArrayList(f64)) void {
        for (data.items) |value| {
            self.pushEle(value);
        }
    }

    fn pushTableData(self: *RunningStat, data: *std.ArrayList(Data)) void {
        for (data.items) |value| {
            self.pushEle(value.asNum().?);
        }
    }

    fn mean(self: *RunningStat) f64 {
        // Computes the current mean of `self`.
        return self.mom1;
    }

    fn variance(self: *RunningStat) f64 {
        // Computes the current population variance of `self`.
        const n_float = @as(f64, @floatFromInt(self.n));
        return self.mom2 / n_float;
    }

    fn varianceS(self: *RunningStat) f64 {
        // Computes the current sample variance of `self`.
        if (self.n > 1) {
            return self.mom2 / @as(f64, @floatFromInt(self.n - 1));
        } else {
            return 0.0;
        }
    }

    fn standardDeviation(self: *RunningStat) f64 {
        // Computes the current population standard deviation of `self`.
        return math.sqrt(self.variance());
    }

    fn standardDeviationS(self: *RunningStat) f64 {
        // Computes the current sample standard deviation of `self`.
        return math.sqrt(self.varianceS());
    }

    fn skewness(self: *RunningStat) f64 {
        // Computes the current population skewness of `self`.
        const n_float = @as(f64, @floatFromInt(self.n));
        return math.sqrt(n_float) * self.mom3 / math.pow(f64, self.mom2, 1.5);
    }

    fn skewnessS(self: *RunningStat) f64 {
        // Computes the current sample skewness of `self`.
        const n_float = @as(f64, @floatFromInt(self.n));
        const s2 = self.skewness();
        return math.sqrt(n_float*(n_float-1))*s2 / (n_float-2);
    }

    fn kurtosis(self: *RunningStat) f64 {
        // Computes the current population kurtosis of `self`.
        const n_float = @as(f64, @floatFromInt(self.n));
        return n_float * self.mom4 / (self.mom2 * self.mom2) - 3.0;
    }

    fn kurtosisS(self: *RunningStat) f64 {
        // Computes the current sample kurtosis of `self`.
        const n_float = @as(f64, @floatFromInt(self.n));
        return (n_float-1) / ((n_float-2)*(n_float-3)) * ((n_float+1)*self.kurtosis() + 6);
    }
};

test "RunningStat struct and methods" {
    const a = std.testing.allocator;
    const expect = std.testing.expect;

    var list: std.ArrayList(f64) = .empty;
    defer list.deinit(a);
    try list.append(a, 1.0);
    try list.append(a, 2.0);
    try list.append(a, 1.0);
    try list.append(a, 4.0);
    try list.append(a, 1.0);
    try list.append(a, 4.0);
    try list.append(a, 1.0);
    try list.append(a, 2.0);

    var runningStat: RunningStat = .{};
    runningStat.pushData(&list);
    const tolerance = 0.00001;

    try expect(runningStat.n == 8);
    try std.testing.expectApproxEqAbs(runningStat.mean(), 2.0, tolerance);
    try std.testing.expectApproxEqAbs(runningStat.variance(), 1.5, tolerance);
    try std.testing.expectApproxEqAbs(runningStat.varianceS(), 1.714285714285715, tolerance);
    try std.testing.expectApproxEqAbs(runningStat.skewness(), 0.8164965809277261, tolerance);
    try std.testing.expectApproxEqAbs(runningStat.skewnessS(), 1.018350154434631, tolerance);
    try std.testing.expectApproxEqAbs(runningStat.kurtosis(), -1.0, tolerance);
    try std.testing.expectApproxEqAbs(runningStat.kurtosisS(), -0.7000000000000008, tolerance);
}

const Statistics = struct {
    running: RunningStat,
    variance: f64,
    varianceS: f64,
    skewness: f64,
    skewnessS: f64,
    kurtosis: f64,
    kurtosisS: f64,
};

// const RunningRegress = struct { // An accumulator for regression calculations.
//     n: usize,                   // amount of pushed data
//     x_stats: RunningStat,       // stats for the first set of data
//     y_stats: RunningStat,       // stats for the second set of data
//     s_xy: f64,                  // accumulated data for combined xy
// };

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
        // copy instead of doing it ourselves
        const copied_table_id = switch (try table_methods.copy(vm, table_id)) {
            .ok => |v| v.asTable().?,
            .err => |e| return .{ .err = e },
        };

        // can safely unwrap because sort() does not return an error
        const res = (try table_methods.sort(vm, @enumFromInt(copied_table_id))).ok.asTable().?;

        // good hygiene to drill the latest id you have
        const sorted_table = try vm.tables.get(res);
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

    // stats:mode() -> num
    // Most frequent occuring value of input data.
    pub fn mode(vm: *VM, table_id: Ts.table) !HostResult {
        const table = try vm.tables.get(@intFromEnum(table_id));
        const data = table.array.items;

        if (data.len == 0) {
            return .errType(
                0,
                "table with at least 1 element",
                "no mode for empty table",
            );
        }

        var freq = std.AutoHashMap(Data, usize).init(vm.runtime.alloc);
        defer freq.deinit();

        var mode_val: Data = data[0];
        var max_freq: usize = 0;

        for (data) |value| {
            const entry = try freq.getOrPut(value);

            if (!entry.found_existing) {
                entry.value_ptr.* = 1;
            } else {
                entry.value_ptr.* += 1;
            }

            const count = entry.value_ptr.*;

            // match numpy behaviour, on ties it'll choose the smaller value
            if (count > max_freq or
                (count == max_freq and vm.compare(value, mode_val) == .lt))
            {
                max_freq = count;
                mode_val = value;
            }
        }

        return .data(mode_val);
    }

    // stats:variance() -> num
    // Population variance of the data.
    pub fn variance(vm: *VM, table_id: Ts.table) !HostResult {
        const table = try vm.tables.get(@intFromEnum(table_id));

        var runningStat: RunningStat = .{};
        runningStat.pushTableData(&table.array);

        return .data(Data.new.num(runningStat.variance()));
    }
};

pub const impls: []const api.Impl = root.impls(Impl).val;
// ++ &.{
// .{ .name = "fmean", .f = root.define(&.{ .table }, fmean) },
// .{ .name = "geometric_mean", .f = root.define(&.{ .table }, geometric_mean) },
// .{ .name = "harmonic_mean", .f = root.defineVariadic(&.{.table}, harmonic_mean) },
// .{ .name = "median_low", .f = root.define(&.{ .table }, median_low) },
// .{ .name = "median_high", .f = root.define(&.{ .table }, median_high) },
// .{ .name = "median_grouped", .f = root.define(&.{.table}, median_grouped) },
// .{ .name = "multimode", .f = root.define(&.{ .table }, multimode) },
// .{ .name = "quantiles", .f = root.define(&.{.table}, quantiles) },
// .{ .name = "stdev", .f = root.define(&.{ .table }, stdev) },
// .{ .name = "covariance", .f = root.define(&.{ .table }, covariance) },
// .{ .name = "correlation", .f = root.define(&.{.table}, correlation) },
// .{ .name = "linear_regression", .f = root.define(&.{.table}, linear_regression) },
// };

test "stats methods" {
    try testing.topTrue("{1, 1, 1, 2, 3, 3} |> stats.frequencies() == {1=3, 2=1, 3=2}");
    try testing.topTrue("{1, 1, 1, 2, 3} |> stats.mean() == 1.6");
    try testing.topTrue("{3, 1, 2, 1, 1} |> stats.median() == 1");
    try testing.topTrue("{3, 1, 2, 1, 3, 1} |> stats.median() == 1.5");
    try testing.topTrue("{3, 1, 2, 1, 3, 1} |> stats.mode() == 1");
    try testing.topTrue("{1, 1, 2, 2} |> stats.mode() == 1");
    try testing.topTrue("{1.0, 2.0, 1.0, 4.0, 1.0, 4.0, 1.0, 2.0} |> stats.mean() == 2.0");
    try testing.topTrue("{1.0, 2.0, 1.0, 4.0, 1.0, 4.0, 1.0, 2.0} |> stats.variance() == 1.5");
    // try testing.topTrue("{1.0, 2.0, 1.0, 4.0, 1.0, 4.0, 1.0, 2.0} |> stats.svariance() == 1.714285714285715")
    // try testing.topTrue("{1.0, 2.0, 1.0, 4.0, 1.0, 4.0, 1.0, 2.0} |> stats.skewness() == 0.8164965809277261")
    // try testing.topTrue("{1.0, 2.0, 1.0, 4.0, 1.0, 4.0, 1.0, 2.0} |> stats.sskewness() == 1.018350154434631")
    // try testing.topTrue("{1.0, 2.0, 1.0, 4.0, 1.0, 4.0, 1.0, 2.0} |> stats.kurtosis() == -1.0")
    // try testing.topTrue("{1.0, 2.0, 1.0, 4.0, 1.0, 4.0, 1.0, 2.0} |> stats.skurtosis() == -0.7000000000000008")
}

// fmean(data, weights=None)
// Fast, floating-point arithmetic mean, with optional weighting.

// geometric_mean(data)
// Geometric mean of data.

// harmonic_mean(data, weights=None)
// Harmonic mean of data.

// median_low(data)
// Low median of data.

// median_high(data)
// High median of data.

// median_grouped(data, interval=1.0)
// Median (50th percentile) of grouped data.

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
