const Ts = root.T;

pub const Impl = struct {
    pub fn @"is_nan?"(vm: *VM, n: Ts.number) !HostResult {
        _ = vm;
        return ._bool(std.math.isNan(n));
    }
    pub fn @"is_finite?"(vm: *VM, n: Ts.number) !HostResult {
        _ = vm;
        return ._bool(std.math.isFinite(n));
    }
    pub fn @"is_inf?"(vm: *VM, n: Ts.number) !HostResult {
        _ = vm;
        return ._bool(std.math.isInf(n));
    }
    pub fn floor(vm: *VM, n: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(@floor(n)));
    }
    pub fn ceil(vm: *VM, n: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(@ceil(n)));
    }
    pub fn round(vm: *VM, n: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(@round(n)));
    }
    pub fn abs(vm: *VM, n: Ts.number) !HostResult {
        _ = vm;
        return .data(Data.new.num(@abs(n)));
    }
    pub fn __call(vm: *VM, self: Ts.any, val: Ts.any) !HostResult {
        _ = self;
        return root.number_(&.{val}, vm);
    }
};

pub const impls = root.impls(Impl).val;

test "number module and metatable" {
    try testing.topNumber("unwrap(number(\"12\"))", 12);
    try testing.topNumber("unwrap(number(3.5))", 3.5);
    try testing.topTrue("number.is_nan?(unwrap(number(\"nan\")))");
    try testing.topTrue("unwrap(number(\"nan\")):is_nan?()");
    try testing.topFalse("42:is_nan?()");
    try testing.topTrue("42:is_finite?()");
    try testing.topFalse("42:is_inf?()");
    try testing.topTrue("unwrap(number(\"inf\")):is_inf?()");
    try testing.topNumber("3.7:floor()", 3);
    try testing.topNumber("3.2:ceil()", 4);
    try testing.topNumber("3.5:round()", 4);
    try testing.topNumber("(-3):abs()", 3);
    try testing.topNumber("number.abs(-7)", 7);
}

const std = @import("std");

const revo = @import("../root.zig");
const testing = revo.lang.testing;
const Data = revo.Data;
const VM = revo.VM;
const api = @import("api.zig");
const root = @import("root.zig");
const HostResult = root.HostResult;
