const std = @import("std");
const revo = @import("../root.zig");
const root = @import("root.zig");
const api = @import("api.zig");
const testing = revo.lang.testing;

const Ts = root.T;
const Data = revo.Data;
const VM = revo.VM;
const HostResult = root.HostResult;

pub const Impl = struct {
    pub fn set_seed(vm: *VM, raw_arg: Ts.number) !HostResult {
        const new_seed: u64 = root.numToInt(u64, raw_arg) orelse return .errType(0, "non-negative integer", root.typeof(Data.new.num(raw_arg), vm));
        vm.runtime.rng_prng = std.Random.DefaultPrng.init(new_seed);
        return .data(Data.new.nil());
    }

    pub fn revert_seed(vm: *VM) !HostResult {
        vm.runtime.rng_prng = null;
        return .data(Data.new.nil());
    }

    pub fn rand(vm: *VM, raw_arg: Ts.number) !HostResult {
        const upper_bound: isize = root.numToInt(isize, raw_arg) orelse return .errType(0, "integer num", root.typeof(Data.new.num(raw_arg), vm));
        return .data(Data.new.num(randomNumber(isize, vm, 0, upper_bound)));
    }

    pub fn range(vm: *VM, raw_lower: Ts.number, raw_upper: Ts.number) !HostResult {
        const lower_bound: isize = root.numToInt(isize, raw_lower) orelse return .errType(0, "integer num", root.typeof(Data.new.num(raw_lower), vm));
        const upper_bound: isize = root.numToInt(isize, raw_upper) orelse return .errType(1, "integer num", root.typeof(Data.new.num(raw_upper), vm));
        const result = if (lower_bound < upper_bound)
            randomNumber(isize, vm, lower_bound, upper_bound)
        else
            randomNumber(isize, vm, upper_bound, lower_bound);
        return .data(Data.new.num(result));
    }

    pub fn rand_float(vm: *VM) !HostResult {
        return .data(Data.new.num(randomNumber(f64, vm, 0.0, 1.0)));
    }

    pub fn choice(vm: *VM, self: Ts.table) !HostResult {
        const table = try vm.tables.get(@intFromEnum(self));
        if (table.array.items.len > 0) {
            const idx = randomNumber(usize, vm, 0, table.array.items.len - 1);
            return .data(table.array.items[idx]);
        } else {
            return .data(Data.new.nil());
        }
    }
};

pub const impls: []const api.Impl = root.impls(Impl).val;

fn randomNumber(comptime T: type, vm: *VM, lowerBound: T, upperBound: T) T {
    if (vm.runtime.rng_prng == null) {
        const time_seed: u64 = @intCast(std.Io.Clock.awake.now(vm.runtime.io).toNanoseconds());
        vm.runtime.rng_prng = std.Random.DefaultPrng.init(time_seed);
    }
    var random = vm.runtime.rng_prng.?.random();
    return switch (@typeInfo(T)) {
        .int => random.intRangeAtMost(T, lowerBound, upperBound),
        .float => random.float(T),
        else => unreachable,
    };
}

test "getting random element from table" {
    try testing.topNumber(
        \\ rng.set_seed(2226)
        \\ const elem = rng.choice({1, 2, 3})
        \\ elem
    , 3);
}

test "nil from a table with only named members" {
    try testing.topTrue(
        \\ let t = {"hi" = 1, "bye" = 2}
        \\ let result = :true
        \\
        \\ for _ in 0..100 
        \\   result = result and rng.choice(t) == :nil
        \\
        \\ result
    );
}

test "seed setting and resetting" {
    try testing.topTrue(
        \\ rng.set_seed(2226)
        \\ let x_total = 0 
        \\
        \\ for x in 0..10 
        \\   x_total += rng.rand(x)
        \\
        \\ rng.set_seed(7)
        \\ let y_total = 0
        \\
        \\ for y in 0..10
        \\   y_total += rng.rand(y)
        \\
        \\ x_total == 16 and y_total == 24
    );
}
