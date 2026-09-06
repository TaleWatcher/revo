const Ts = root.T;

pub const Impl = struct {
    pub fn abs(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(@abs(x)));
    }
    pub fn floor(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(@floor(x)));
    }
    pub fn ceil(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(@ceil(x)));
    }
    pub fn sqrt(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(@sqrt(x)));
    }
    pub fn pow(vm: *VM, base: Ts.number, exponent: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(std.math.pow(f64, base, exponent)));
    }
    pub fn sin(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(@sin(x)));
    }
    pub fn asin(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(std.math.asin(x)));
    }
    pub fn sinh(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(std.math.sinh(x)));
    }
    pub fn asinh(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(std.math.asinh(x)));
    }
    pub fn cos(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(@cos(x)));
    }
    pub fn acos(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(std.math.acos(x)));
    }
    pub fn cosh(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(std.math.cosh(x)));
    }
    pub fn acosh(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(std.math.acosh(x)));
    }
    pub fn tan(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(@tan(x)));
    }
    pub fn atan(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(std.math.atan(x)));
    }
    pub fn tanh(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(std.math.tanh(x)));
    }
    pub fn atanh(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(std.math.atanh(x)));
    }
    pub fn atan2(vm: *VM, y: Ts.number, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(std.math.atan2(y, x)));
    }
    pub fn hypot(vm: *VM, x: Ts.number, y: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(std.math.hypot(x, y)));
    }
    pub fn log(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(@log(x)));
    }
    pub fn exp(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(@exp(x)));
    }
    pub fn sign(vm: *VM, x: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(std.math.sign(x)));
    }
};

pub const impls: []const api.Impl = root.impls(Impl).val ++ &[_]api.Impl{
    .{ .name = "min", .f = root.defineVariadic(&.{.number}, minFn) },
    .{ .name = "max", .f = root.defineVariadic(&.{.number}, maxFn) },
};

fn minFn(args: []const Data, _: *VM) !HostResult {
    var res = args[0].asNum().?;
    for (args[1..]) |arg| {
        const val = arg.asNum().?;
        if (val < res) res = val;
    }
    return .data(Data.new.num(res));
}

fn maxFn(args: []const Data, _: *VM) !HostResult {
    var res = args[0].asNum().?;
    for (args[1..]) |arg| {
        const val = arg.asNum().?;
        if (val > res) res = val;
    }
    return .data(Data.new.num(res));
}

test "math library" {
    try testing.topNumber("math.abs(-5)", 5);
    try testing.topNumber("math.abs(5)", 5);
    try testing.topNumber("math.floor(3.7)", 3);
    try testing.topNumber("math.ceil(3.2)", 4);
    try testing.topNumber("math.sqrt(4)", 2);
    try testing.topNumber("math.pow(2, 3)", 8);
    try testing.topNumber("math.min(1, 2, 3)", 1);
    try testing.topNumber("math.max(1, 2, 3)", 3);
    try testing.topNumber("math.hypot(3, 4)", 5.0);
    try testing.topNumber("math.sign(-0.15)", -1);
}

const std = @import("std");

const revo = @import("../root.zig");
const testing = revo.lang.testing;
const Data = revo.Data;
const VM = revo.VM;
const api = @import("api.zig");
const root = @import("root.zig");
const HostResult = root.HostResult;
const typeof = root.typeof;
