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
const Table = revo.table.Table;
const testing = revo.lang.testing;
const table_methods = table_std.Impl;

// An accumulator for statistical data.
const RunningStats = struct {
    // amount of pushed data
    n: usize = 0,
    // self-explaining
    min: f64 = 0.0,
    max: f64 = 0.0,
    sum: f64 = 0.0,
    ssq: f64 = 0.0,
    prd: f64 = 0.0,
    // statistical moments, mom1 is mean
    mom1: f64 = 0.0,
    mom1_comp: f64 = 0.0,
    mom2: f64 = 0.0,
    mom3: f64 = 0.0,
    mom4: f64 = 0.0,
    // hashmap for tracking frequencies
    freq: std.AutoHashMap(u64, usize),
    imode: f64 = undefined,
    imode_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) RunningStats {
        return .{
            .freq = std.AutoHashMap(u64, usize).init(allocator),
        };
    }
    pub fn deinit(self: *RunningStats) void {
        self.freq.deinit();
    }

    fn pushEle(self: *RunningStats, x: f64) !void {
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
        self.ssq += x * x;
        if (self.n == 1) {
            self.prd = x;
        } else {
            self.prd *= x;
        }

        const entry = try self.freq.getOrPut(@bitCast(x));
        if (!entry.found_existing) {
            entry.value_ptr.* = 1;
        } else {
            entry.value_ptr.* += 1;
        }
        const this_count = entry.value_ptr.*;
        // match numpy behaviour, on ties it'll choose the smaller value
        if (this_count > self.imode_count or
            (this_count == self.imode_count and x < self.imode))
        {
            self.imode_count = this_count;
            self.imode = x;
        }

        const n_float = @as(f64, @floatFromInt(self.n));
        const nm1_float = @as(f64, @floatFromInt(self.n - 1));
        const delta = x - self.mom1;
        const delta_n = (delta / n_float) - self.mom1_comp;
        const delta_n2 = delta_n * delta_n;
        const term1 = delta * delta_n * nm1_float;
        self.mom4 += term1 * delta_n2 * (n_float * n_float - 3 * n_float + 3) + 6 * delta_n2 * self.mom2 - 4 * delta_n * self.mom3;
        self.mom3 += term1 * delta_n * (n_float - 2) - 3 * delta_n * self.mom2;
        self.mom2 += term1;
        // mean compensation for tail-end precision
        const next_mom1 = self.mom1 + delta_n;
        self.mom1_comp = (next_mom1 - self.mom1) - delta_n;
        self.mom1 = next_mom1;
    }

    fn pushData(self: *RunningStats, data: *std.ArrayList(f64)) !void {
        for (data.items) |value| {
            try self.pushEle(value);
        }
    }

    // callers to surface a proper HostResult error instead of panicking
    // when the table contains a non-numeric element
    fn pushTableData(self: *RunningStats, data: *std.ArrayList(Data)) !void {
        for (data.items) |value| {
            const num = value.asNum() orelse return error.NonNumericValue;
            try self.pushEle(num);
        }
    }

    fn mean(self: *RunningStats) f64 {
        // Computes the current mean of `self`.
        return self.mom1;
    }

    fn mode(self: *RunningStats) f64 {
        // Computes the current mode of `self`.
        return self.imode;
    }

    fn variance(self: *RunningStats) f64 {
        // Computes the current population variance of `self`.
        const n_float = @as(f64, @floatFromInt(self.n));
        return self.mom2 / n_float;
    }

    fn varianceS(self: *RunningStats) f64 {
        // Computes the current sample variance of `self`.
        if (self.n <= 1) return 0.0;

        const n_float = @as(f64, @floatFromInt(self.n));
        const nm1_float = n_float - 1.0;
        return self.mom2 / nm1_float;
    }

    fn standardDeviation(self: *RunningStats) f64 {
        // Computes the current population standard deviation of `self`.
        return math.sqrt(self.variance());
    }

    fn standardDeviationS(self: *RunningStats) f64 {
        // Computes the current sample standard deviation of `self`.
        return math.sqrt(self.varianceS());
    }

    fn skewness(self: *RunningStats) f64 {
        // Computes the current population skewness of `self`.
        const n_float = @as(f64, @floatFromInt(self.n));
        return math.sqrt(n_float) * self.mom3 / math.pow(f64, self.mom2, 1.5);
    }

    fn skewnessS(self: *RunningStats) f64 {
        // Computes the current sample skewness of `self`.
        if (self.n <= 2) return 0.0;

        const n_float = @as(f64, @floatFromInt(self.n));
        const nm2_float = n_float - 2.0;
        const s2 = self.skewness();
        return math.sqrt(n_float * (n_float - 1)) * s2 / nm2_float;
    }

    fn kurtosis(self: *RunningStats) f64 {
        // Computes the current population kurtosis of `self`.
        const n_float = @as(f64, @floatFromInt(self.n));
        return n_float * self.mom4 / (self.mom2 * self.mom2) - 3.0;
    }

    fn kurtosisS(self: *RunningStats) f64 {
        // Computes the current sample kurtosis of `self`.
        if (self.n <= 3) return 0.0;

        const n_float = @as(f64, @floatFromInt(self.n));
        const nm1_float = n_float - 1.0;
        const np1_float = n_float + 1.0;
        const nm2_x_nm3_float = (n_float - 2.0) * (n_float - 3.0);
        return nm1_float / nm2_x_nm3_float * (np1_float * self.kurtosis() + 6);
    }
};

test "RunningStats struct and methods" {
    const a = std.testing.allocator;
    const expect = std.testing.expect;

    var list: std.ArrayList(f64) = .empty;
    defer list.deinit(a);
    try list.appendSlice(a, &.{ 1.0, 2.0, 1.0, 4.0, 1.0, 4.0, 1.0, 2.0 });

    var runningStats: RunningStats = RunningStats.init(a);
    defer runningStats.deinit();
    try runningStats.pushData(&list);
    const tolerance = 0.00001;

    try expect(runningStats.n == 8);
    try std.testing.expectApproxEqAbs(runningStats.mean(), 2.0, tolerance);
    try std.testing.expectApproxEqAbs(runningStats.variance(), 1.5, tolerance);
    try std.testing.expectApproxEqAbs(runningStats.varianceS(), 1.714285714285715, tolerance);
    try std.testing.expectApproxEqAbs(runningStats.skewness(), 0.8164965809277261, tolerance);
    try std.testing.expectApproxEqAbs(runningStats.skewnessS(), 1.018350154434631, tolerance);
    try std.testing.expectApproxEqAbs(runningStats.kurtosis(), -1.0, tolerance);
    try std.testing.expectApproxEqAbs(runningStats.kurtosisS(), -0.7000000000000008, tolerance);
}

// const RunningRegress = struct { // An accumulator for regression calculations.
//     n: usize,                   // amount of pushed data
//     x_stats: RunningStats,       // stats for the first set of data
//     y_stats: RunningStats,       // stats for the second set of data
//     s_xy: f64,                  // accumulated data for combined xy
// };

pub const Impl = struct {
    fn buildStats(vm: *VM, table_id: Ts.table) !RunningStats {
        const table = try vm.tables.get(@intFromEnum(table_id));

        if (table.array.items.len == 0) {
            return error.EmptyTable;
        }

        var runningStats: RunningStats = RunningStats.init(vm.runtime.alloc);
        errdefer runningStats.deinit();
        try runningStats.pushTableData(&table.array);
        return runningStats;
    }

    /// convert a zig error into a HostResult.err for correctness
    /// malformed input has to return a .err error instead of throwing a zig error
    fn statsErrResult(e: anyerror) !HostResult {
        switch (e) {
            error.EmptyTable => return .errType(0, "table with at least 1 element", "no statistics for empty data"),
            error.NonNumericValue => return .errType(0, "table of numbers", "table contains a non-numeric value"),
            else => return e,
        }
    }

    fn numStat(vm: *VM, table_id: Ts.table, comptime compute: fn (*RunningStats) f64) !HostResult {
        var runningStats = buildStats(vm, table_id) catch |e| return statsErrResult(e);
        defer runningStats.deinit();
        return .data(Data.new.num(compute(&runningStats)));
    }

    /// > stats.frequencies(table) -> table<any>
    /// returns a histogram of element frequencies as table (ele: freq)
    pub fn frequencies(vm: *VM, table_id: Ts.table) !HostResult {
        var runningStats = buildStats(vm, table_id) catch |e| return statsErrResult(e);
        defer runningStats.deinit();

        const result_table_id = try vm.tables.create();
        const result_table = try vm.tables.get(result_table_id);

        var freq_it = runningStats.freq.iterator();
        while (freq_it.next()) |entry| {
            try result_table.put(result_table_id, vm, Data.new.num(@as(f64, @bitCast(entry.key_ptr.*))), Data.new.num(entry.value_ptr.*));
        }

        return .data(Data.new.table(result_table_id));
    }

    // stats.mean(table) -> num
    // Arithmetic mean (“average”) of data.
    pub fn mean(vm: *VM, table_id: Ts.table) !HostResult {
        return numStat(vm, table_id, RunningStats.mean);
    }

    // stats.median(table) -> num
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

    // -- [wrappers] ----------------------------------------------------------
    // do not comptime inline-for this in impls
    //

    // stats.mode(table) -> num
    // Most frequent occuring value of input data.
    pub fn mode(vm: *VM, table_id: Ts.table) !HostResult {
        return numStat(vm, table_id, RunningStats.mode);
    }

    // stats.variance(table) -> num
    // Population variance of the data.
    pub fn variance(vm: *VM, table_id: Ts.table) !HostResult {
        return numStat(vm, table_id, RunningStats.variance);
    }

    // stats.sample_variance(table) -> num
    // Sample variance of the data.
    pub fn sample_variance(vm: *VM, table_id: Ts.table) !HostResult {
        return numStat(vm, table_id, RunningStats.varianceS);
    }

    // stats.stdev(table) -> num
    // Population standard deviation of the data.
    pub fn stdev(vm: *VM, table_id: Ts.table) !HostResult {
        return numStat(vm, table_id, RunningStats.standardDeviation);
    }

    // stats.sample_stdev(table) -> num
    // Sample standard deviation of the data.
    pub fn sample_stdev(vm: *VM, table_id: Ts.table) !HostResult {
        return numStat(vm, table_id, RunningStats.standardDeviationS);
    }

    // stats.skewness(table) -> num
    // Population skewness of the data.
    pub fn skewness(vm: *VM, table_id: Ts.table) !HostResult {
        return numStat(vm, table_id, RunningStats.skewness);
    }

    // stats.sample_skewness(table) -> num
    // Sample skewness of the data.
    pub fn sample_skewness(vm: *VM, table_id: Ts.table) !HostResult {
        return numStat(vm, table_id, RunningStats.skewnessS);
    }

    // stats.kurtosis(table) -> num
    // Population kurtosis of the data.
    pub fn kurtosis(vm: *VM, table_id: Ts.table) !HostResult {
        return numStat(vm, table_id, RunningStats.kurtosis);
    }

    // stats.sample_kurtosis(table) -> num
    // Sample kurtosis of the data.
    pub fn sample_kurtosis(vm: *VM, table_id: Ts.table) !HostResult {
        return numStat(vm, table_id, RunningStats.kurtosisS);
    }

    // stats.statistics(table) -> table
    // table of all statistics of the input data
    pub fn statistics(vm: *VM, table_id: Ts.table) !HostResult {
        var runningStats = buildStats(vm, table_id) catch |e| return statsErrResult(e);
        defer runningStats.deinit();

        const result_table_id = try vm.tables.create();
        const result_table = try vm.tables.get(result_table_id);
        const freq_table_id = try vm.tables.create();
        const freq_table = try vm.tables.get(freq_table_id);

        var freq_it = runningStats.freq.iterator();
        while (freq_it.next()) |entry| {
            try freq_table.put(freq_table_id, vm, Data.new.num(@as(f64, @bitCast(entry.key_ptr.*))), Data.new.num(entry.value_ptr.*));
        }

        try result_table.put(result_table_id, vm, try vm.dataAtom("frequencies"), Data.new.table(freq_table_id));
        try result_table.put(result_table_id, vm, try vm.dataAtom("mean"), Data.new.num(runningStats.mean()));
        try result_table.put(result_table_id, vm, try vm.dataAtom("median"), (try median(vm, table_id)).ok);
        try result_table.put(result_table_id, vm, try vm.dataAtom("mode"), Data.new.num(runningStats.mode()));
        try result_table.put(result_table_id, vm, try vm.dataAtom("stdev"), Data.new.num(runningStats.standardDeviation()));
        try result_table.put(result_table_id, vm, try vm.dataAtom("sample_stdev"), Data.new.num(runningStats.standardDeviationS()));
        try result_table.put(result_table_id, vm, try vm.dataAtom("variance"), Data.new.num(runningStats.variance()));
        try result_table.put(result_table_id, vm, try vm.dataAtom("sample_variance"), Data.new.num(runningStats.varianceS()));
        try result_table.put(result_table_id, vm, try vm.dataAtom("skewness"), Data.new.num(runningStats.skewness()));
        try result_table.put(result_table_id, vm, try vm.dataAtom("sample_skewness"), Data.new.num(runningStats.skewnessS()));
        try result_table.put(result_table_id, vm, try vm.dataAtom("kurtosis"), Data.new.num(runningStats.kurtosis()));
        try result_table.put(result_table_id, vm, try vm.dataAtom("sample_kurtosis"), Data.new.num(runningStats.kurtosisS()));

        return .data(Data.new.table(result_table_id));
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
    try testing.topTrue("{1.5, 2.5, 2.5, 2.75, 3.25, 4.75} |> stats.stdev() == 0.986893273527251");
    try testing.topTrue("{1.5, 2.5, 2.5, 2.75, 3.25, 4.75} |> stats.sample_stdev() == 1.0810874155219827");
    try testing.topTrue("{1.0, 2.0, 1.0, 4.0, 1.0, 4.0, 1.0, 2.0} |> stats.variance() |> math.is_close?(1.5, 6)");
    try testing.topTrue("{1.0, 2.0, 1.0, 4.0, 1.0, 4.0, 1.0, 2.0} |> stats.sample_variance() |> math.is_close?(1.714285714285715, 15)");
    try testing.topTrue("{1.0, 2.0, 1.0, 4.0, 1.0, 4.0, 1.0, 2.0} |> stats.skewness() |> math.is_close?(0.8164965809277261, 16)");
    try testing.topTrue("{1.0, 2.0, 1.0, 4.0, 1.0, 4.0, 1.0, 2.0} |> stats.sample_skewness() |> math.is_close?(1.018350154434631, 15)");
    try testing.topTrue("{1.0, 2.0, 1.0, 4.0, 1.0, 4.0, 1.0, 2.0} |> stats.kurtosis() |> math.is_close?(-1.0, 1)");
    try testing.topTrue("{1.0, 2.0, 1.0, 4.0, 1.0, 4.0, 1.0, 2.0} |> stats.sample_kurtosis() |> math.is_close?(-0.7000000000000008, 16)");
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
