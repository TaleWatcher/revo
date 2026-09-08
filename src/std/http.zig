const std = @import("std");
const revo = @import("../root.zig");
const root = @import("root.zig");
const api = @import("api.zig");

const Ts = root.T;
const Data = revo.Data;
const testing = revo.lang.testing;
const VM = revo.VM;
const HostResult = root.HostResult;

const Uri = std.Uri;
const Client = std.http.Client;
const Table = revo.table.Table;
const Header = std.http.Header;
const Method = std.http.Method;
const RedirectBehavior = std.http.Client.Request.RedirectBehavior;

pub const Impl = struct {
    pub fn fetch(vm: *VM, raw_method: Ts.atom, url: Ts.any, opts: Ts.any) !HostResult {
        const method = buildMethod(raw_method, vm);
        const response_has_body = methodResponseHasBody(method);

        const url_string = switch (try urlToString(url, vm)) {
            .err => |e| return HostResult{ .err = e },
            .value => |v| v,
        };
        const redirects: ?u16 = switch (try buildMaxRedirects(url, vm)) {
            .err => |e| return HostResult{ .err = e },
            .value => |v| v,
        };
        const redirect_behavior =
            if (redirects) |r|
                if (r == 0) .unhandled else RedirectBehavior.init(r)
            else
                .unhandled;

        var client = Client{ .allocator = vm.runtime.alloc, .io = vm.runtime.io };
        defer client.deinit();

        // build fetch request options
        var request: std.http.Client.FetchOptions = .{ .location = .{ .url = url_string }, .method = method, .redirect_behavior = redirect_behavior };

        // add body to the request, if provided
        const body = try buildBody(method, opts, vm);
        if (body) |b| {
            request.payload = b;
            // default the content type to json if it is not set
            if (request.headers.content_type == .default) {
                request.headers.content_type = .{ .override = "application/json" };
            }
        }
        var response_writer = std.Io.Writer.Allocating.init(vm.runtime.alloc);
        defer response_writer.deinit();
        request.response_writer = &response_writer.writer;

        // add provided headers to the request
        const max_headers = 50;
        var extra_headers = try std.ArrayList(std.http.Header).initCapacity(vm.runtime.alloc, max_headers);
        defer extra_headers.deinit(vm.runtime.alloc);
        const headers = switch (try buildHeaders(opts, &extra_headers, vm)) {
            .err => |e| return HostResult{ .err = e },
            .value => |v| v,
        };
        request.headers = headers;
        request.extra_headers = extra_headers.items;

        // fetch the request and build the result
        const response = try client.fetch(request);
        const result_atom = try vm.internAtom(switch (response.status.class()) {
            .informational => "informational",
            .success => "success",
            .redirect => "redirect",
            .client_error => "client_error",
            .server_error => "server_error",
        });
        const status = try vm.tuples.create(&[_]Data{
            Data.new.atom(result_atom),
            Data.new.num(@as(usize, @intFromEnum(response.status))),
        });
        const id = try vm.tables.create();
        var table = try vm.tables.get(id);
        try table.putRawAtom(try vm.internAtom("status"), Data.new.tuple(status), vm);
        if (response_has_body) {
            try table.putRawAtom(try vm.internAtom("body"), try vm.ownDataString(try response_writer.toOwnedSlice()), vm);
        }

        return HostResult.Ok(vm, Data.new.table(id));
    }
};

pub const impls = root.impls(Impl).val;

fn buildMethod(raw_method: Ts.atom, vm: *VM) Method {
    const m = vm.stringValue(@intFromEnum(raw_method));
    if (eqStr("connect", m)) {
        return .CONNECT;
    } else if (eqStr("delete", m)) {
        return .DELETE;
    } else if (eqStr("get", m)) {
        return .GET;
    } else if (eqStr("head", m)) {
        return .HEAD;
    } else if (eqStr("options", m)) {
        return .OPTIONS;
    } else if (eqStr("patch", m)) {
        return .PATCH;
    } else if (eqStr("post", m)) {
        return .POST;
    } else if (eqStr("put", m)) {
        return .PUT;
    } else if (eqStr("trace", m)) {
        return .TRACE;
    } else {
        // unreachable
        // TODO: add custom methods?
        return .GET;
    }
}

/// normalize url param into a string
fn urlToString(url: Data, vm: *VM) !HostErrOr([]const u8) {
    // TODO: Handle URL table
    return if (url.asStr()) |s|
        .{ .value = vm.stringValue(s) }
    else
        .{ .err = HostResult.errType(0, "string or table", revo.std_lib.typeof(url, vm)).err };
}

fn buildMaxRedirects(options: Data, vm: *VM) !HostErrOr(?u16) {
    if (options.asTable()) |options_id| {
        var options_table = try vm.tables.get(options_id);
        if (options_table.getRawAtom(try vm.internAtom("max_redirects"), vm)) |id| {
            if (id.asNum()) |num| {
                const max_redirects: u16 = @trunc(num);
                return .{ .value = max_redirects };
            }
        }
    }
    return .{ .value = null };
}

fn buildHeaders(options: Data, extra_headers: *std.ArrayList(std.http.Header), vm: *VM) !HostErrOr(std.http.Client.Request.Headers) {
    var headers = std.http.Client.Request.Headers{};

    if (options.asTable()) |options_id| {
        var options_table = try vm.tables.get(options_id);
        if (options_table.getRawAtom(try vm.internAtom("headers"), vm)) |id| {
            if (id.asTable()) |table_id| {
                var table: *Table = try vm.tables.get(table_id);
                var it = table.hash.orderedIterator();
                while (it.next()) |header| {
                    const key = try headerToString(header.key, vm);
                    const val = try headerToString(header.val, vm);
                    if (eqStr(key, "Host"))
                        headers.host = .{ .override = val }
                    else if (eqStr(key, "Authorization"))
                        headers.authorization = .{ .override = val }
                    else if (eqStr(key, "User-Agent"))
                        headers.user_agent = .{ .override = val }
                    else if (eqStr(key, "Connection"))
                        headers.connection = .{ .override = val }
                    else if (eqStr(key, "Accept-Encoding"))
                        headers.accept_encoding = .{ .override = val }
                    else if (eqStr(key, "Content-Type"))
                        headers.content_type = .{ .override = val }
                    else
                        try extra_headers.append(vm.runtime.alloc, Header{ .name = key, .value = val });
                }
            }
        }
    }

    return .{ .value = headers };
}

fn buildBody(method: Method, opts: Data, vm: *VM) !?[]const u8 {
    if (method == .GET or method == .HEAD or method == .TRACE) {
        return null;
    }
    if (opts.asTable()) |o| {
        var options_table = try vm.tables.get(o);
        if (options_table.getRawAtom(try vm.internAtom("body"), vm)) |id| {
            if (id.asStr()) |s| {
                return vm.stringValue(s);
            }
        }
    }
    return null;
}

fn HostErrOr(comptime T: type) type {
    return union(enum) {
        value: T,
        err: revo.std_lib.HostErrPayload,
    };
}

fn headerToString(value: Data, vm: *VM) anyerror![]const u8 {
    return switch (value.tag()) {
        .atom => vm.stringValue(value.asAtom().?),
        .string => vm.stringValue(value.asStr().?),
        .number => try std.fmt.allocPrint(vm.runtime.alloc, "{d}", .{value.asNum().?}),
        else => error.InvalidHeaderType,
    };
}

fn methodResponseHasBody(method: Method) bool {
    return switch (method) {
        .CONNECT => false,
        .DELETE => true,
        .GET => true,
        .HEAD => false,
        .OPTIONS => true,
        .PATCH => true,
        .POST => true,
        .PUT => true,
        .TRACE => false,
    };
}

fn eqStr(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
