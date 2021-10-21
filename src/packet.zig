const std = @import("std");
const testing = std.testing;
const buffer = @import("buffer.zig");

const codes = @import("code.zig");
const options = @import("options.zig");

// CoAP version implemented by this library.
//
// From RFC 7252:
//
//  Version (Ver): 2-bit unsigned integer. Indicates the CoAP version
//  number. Implementations of this specification MUST set this field
//  to 1 (01 binary).
//
pub const VERSION: u2 = 1;

// CoAP message type.
//
// From RFC 7252:
//
//  2-bit unsigned integer. Indicates if this message is of type
//  Confirmable (0), Non-confirmable (1), Acknowledgement (2), or Reset
//  (3).
//
pub const Mtype = enum(u2) {
    confirmable = 0,
    non_confirmable = 1,
    acknowledgement = 2,
    reset = 3,
};

pub const Header = packed struct {
    version: u2,
    type: Mtype,
    token_len: u4,
    code: codes.Code,
    message_id: u16,
};

pub const Response = struct {
    header: Header,
    token: []const u8,
    buffer: buffer.WriteBuffer,
    last_option: u32 = 0,

    const DeltaEncoding = union(enum) {
        noExt: u4,
        extByte: u8,
        extHalf: u16,

        fn id(self: DeltaEncoding) u4 {
            switch (self) {
                DeltaEncoding.noExt => |x| return x,
                DeltaEncoding.extByte => return 13,
                DeltaEncoding.extHalf => return 14,
            }
        }

        fn writeExtend(self: DeltaEncoding, wb: *buffer.WriteBuffer) !void {
            switch (self) {
                DeltaEncoding.noExt => {},
                DeltaEncoding.extByte => |x| try wb.byte(x),
                DeltaEncoding.extHalf => |x| try wb.half(x),
            }
        }
    };

    pub fn init(buf: []u8, mtype: Mtype, code: codes.Code, token: []const u8, id: u16) !Response {
        var hdr = Header{
            .version = VERSION,
            .type = mtype,
            .token_len = @intCast(u4, token.len),
            .code = code,
            .message_id = id,
        };

        var r = Response{
            .header = hdr,
            .token = token,
            .buffer = .{ .slice = buf },
        };

        // Convert message ID to network byte order.
        hdr.message_id = std.mem.nativeToBig(u16, hdr.message_id);

        const serialized = @bitCast(u32, hdr);
        try r.buffer.word(serialized);

        // Serialization of token_len is broken due to compiler bug.
        r.buffer.slice[0] = (0x1 << 6) | (@intCast(u8, @enumToInt(mtype)) << 4) | @intCast(u4, token.len);

        return r;
    }

    pub fn encodeValue(self: *Response, val: u32) DeltaEncoding {
        switch (val) {
            0...12 => {
                // From RFC 7252:
                //
                //   A value between 0 and 12 indicates the Option Delta.
                return DeltaEncoding{ .noExt = @intCast(u4, val) };
            },
            13...268 => { // 268 = 2^8 + 13 - 1
                // From RFC 7252:
                //
                //   An 8-bit unsigned integer follows the initial byte and
                //   indicates the Option Delta minus 13.
                return DeltaEncoding{ .extByte = @intCast(u8, (val - 13)) };
            },
            269...65804 => { // 65804 = 2^16 + 269 - 1
                // From RFC 7252:
                //
                //   A 16-bit unsigned integer in network byte order follows the
                //   initial byte and indicates the Option Delta minus 269.
                const v = std.mem.nativeToBig(u16, @intCast(u16, val - 269));
                return DeltaEncoding{ .extHalf = v };
            },
            else => unreachable,
        }
    }

    // TODO: Reset buffer on error (or check that enough space for
    // option is available in advance).
    pub fn addOption(self: *Response, opt: *const options.Option) !void {
        if (self.last_option > opt.number)
            unreachable;
        const delta = opt.number - self.last_option;

        const odelta = self.encodeValue(delta);
        const olen = self.encodeValue(@intCast(u32, opt.value.len));

        // Write first byte of CoAP option format.
        try self.buffer.byte(@as(u8, odelta.id()) << 4 | olen.id());

        // Write extended bits of option delta/length (if any).
        try odelta.writeExtend(&self.buffer);
        try olen.writeExtend(&self.buffer);

        try self.buffer.bytes(opt.value);
        self.last_option = opt.number;
    }

    pub fn marshal(self: *Response) []u8 {
        return self.buffer.slice;
    }
};

test "test header serialization" {
    const exp: []const u8 = &[_]u8{ 0x41, 0x01, 0x09, 0x26 };

    var buf = [_]u8{0} ** exp.len;
    var resp = try Response.init(&buf, Mtype.confirmable, codes.GET, &[_]u8{23}, 2342);

    const serialized = resp.marshal();
    testing.expect(std.mem.eql(u8, serialized, exp));
}

test "test option serialization" {
    const exp: []const u8 = &[_]u8{ 0x40, 0x01, 0x09, 0x26, 0xd2, 0x0a, 0x0d, 0x25, 0xe0, 0xfe, 0xdb };

    var buf = [_]u8{0} ** exp.len;
    var resp = try Response.init(&buf, Mtype.confirmable, codes.GET, &[_]u8{}, 2342);

    const opt1 = options.Option{ .number = 23, .value = &[_]u8{ 13, 37 } };
    try resp.addOption(&opt1);

    const opt2 = options.Option{ .number = 65535, .value = &[_]u8{} };
    try resp.addOption(&opt2);

    const serialized = resp.marshal();
    testing.expect(std.mem.eql(u8, serialized, exp));
}

pub const Request = struct {
    header: Header,
    slice: buffer.ReadBuffer,
    token: ?[]const u8,
    payload: ?*const u8,
    last_option: ?options.Option,

    const MAX_TOKEN_LEN = 8;
    const OPTION_END = 0xff;

    pub fn init(buf: []const u8) !Request {
        var slice = buffer.ReadBuffer{ .slice = buf };
        if (buf.len < @sizeOf(Header))
            return error.FormatError;

        // Cast first four bytes to u32 and convert them to header struct
        const firstByte = slice.slice[0]; // XXX (see below)
        const serialized: u32 = try slice.word();
        var hdr = @bitCast(Header, serialized);

        // Convert message_id to a integer in host byteorder
        hdr.message_id = std.mem.bigToNative(u16, hdr.message_id);

        // TODO: Somehow extraction of the token length does not work
        // via packed structs in Zig 0.7.1 (probably compiler bug).
        hdr.token_len = @intCast(u4, firstByte & 0xf);

        var token: ?[]const u8 = null;
        if (hdr.token_len > 0) {
            if (hdr.token_len > MAX_TOKEN_LEN)
                return error.FormatError;

            token = slice.bytes(hdr.token_len) catch {
                return error.FormatError;
            };
        }

        // For the first instance in a message, a preceding
        // option instance with Option Number zero is assumed.
        const init_option = options.Option{ .number = 0, .value = &[_]u8{} };

        return Request{
            .header = hdr,
            .token = token,
            .slice = slice,
            .payload = null,
            .last_option = init_option,
        };
    }

    // https://datatracker.ietf.org/doc/html/rfc7252#section-3.1
    fn decodeValue(self: *Request, val: u4) !u16 {
        switch (val) {
            13 => {
                // From RFC 7252:
                //
                //  13: An 8-bit unsigned integer follows the initial byte and
                //  indicates the Option Delta minus 13.
                //
                const result = self.slice.byte() catch {
                    return error.FormatError;
                };
                return @as(u16, result + 13);
            },
            14 => {
                // From RFC 7252:
                //
                //  14: A 16-bit unsigned integer in network byte order follows the
                //  initial byte and indicates the Option Delta minus 269.
                //
                const result = self.slice.half() catch {
                    return error.FormatError;
                };
                return std.mem.bigToNative(u16, result) + 269;
            },
            15 => {
                // From RFC 7252:
                //
                //  15: Reserved for future use. If the field is set to this value,
                //  it MUST be processed as a message format error.
                //
                return error.PayloadMarker;
            },
            else => {
                return val;
            },
        }
    }

    // TODO: comptime to enforce order of functions calls (e.g. no nextOption after skipOptions)
    fn nextOption(self: *Request) !?options.Option {
        if (self.last_option == null)
            return null;

        const option = self.slice.byte() catch {
            return error.EndOfStream;
        };
        if (option == OPTION_END) {
            self.last_option = null;
            if (self.slice.length() < 1) {
                // For zero-length payload OPTION_END should not be set.
                return error.InvalidPayload;
            } else {
                self.payload = try self.slice.ptr();
            }
            return null;
        }

        const delta = try self.decodeValue(@intCast(u4, option >> 4));
        const len = try self.decodeValue(@intCast(u4, option & 0xf));

        var optnum = self.last_option.?.number + delta;
        var optval = self.slice.bytes(len) catch {
            return error.FormatError;
        };

        const ret = options.Option{
            .number = optnum,
            .value = optval,
        };

        self.last_option = ret;
        return ret;
    }

    pub fn findOption(self: *Request, optnum: u32) !options.Option {
        if (optnum == 0)
            return error.InvalidArgument;
        if (self.last_option == null)
            return error.EndOfOptions;

        const n = self.last_option.?.number;
        if (n > 0 and n >= optnum)
            return error.InvalidArgument;

        while (true) {
            const next = try self.nextOption();
            if (next == null)
                return error.EndOfOptions;

            const opt = next.?;
            if (opt.number == optnum) {
                return opt;
            } else if (opt.number > optnum) {
                return error.OptionNotFound;
            }
        }
    }

    pub fn skipOptions(self: *Request) !void {
        while (true) {
            var opt = self.nextOption() catch |err| {
                // The absence of the Payload Marker denotes a zero-length payload.
                if (err == error.EndOfStream)
                    return error.ZeroLengthPayload;
                return err;
            };
            if (opt == null)
                break;
        }
    }
};

test "test header parser" {
    const buf: []const u8 = &[_]u8{ 0x41, 0x01, 0x09, 0x26, 0x17 };
    const req = try Request.init(buf);
    const hdr = req.header;

    testing.expect(hdr.version == VERSION);
    testing.expect(hdr.type == Mtype.confirmable);
    testing.expect(hdr.token_len == 1);
    testing.expect(req.token.?[0] == 23);
    testing.expect(hdr.code.equal(codes.GET));
    testing.expect(hdr.message_id == 2342);
}

test "test payload parsing" {
    const buf: []const u8 = &[_]u8{ 0x62, 0x03, 0x04, 0xd2, 0xdd, 0x64, 0xff, 0x17, 0x2a, 0x0d, 0x25 };
    var req = try Request.init(buf);

    try req.skipOptions();
    testing.expect(req.payload.? == &buf[7]);
}

test "test option parser" {
    const buf: []const u8 = &[_]u8{ 0x41, 0x01, 0x09, 0x26, 0x17, 0xd2, 0x0a, 0x0d, 0x25 };
    var req = try Request.init(buf);

    const next_opt = try req.nextOption();
    const opt = next_opt.?;
    const val = opt.value;

    testing.expect(opt.number == 23);
    testing.expect(val.len == 2);
    testing.expect(val[0] == 13);
    testing.expect(val[1] == 37);
}

test "test findOption" {
    const buf: []const u8 = &[_]u8{ 0x51, 0x01, 0x30, 0x39, 0x05, 0xd4, 0x0a, 0x01, 0x02, 0x03, 0x04, 0xd1, 0x06, 0x17, 0x81, 0x01 };
    var req = try Request.init(buf);

    // First option
    const opt1 = try req.findOption(23);
    testing.expect(opt1.number == 23);
    const exp1: []const u8 = &[_]u8{ 1, 2, 3, 4 };
    testing.expect(std.mem.eql(u8, exp1, opt1.value));

    // Third option, skipping second
    const opt3 = try req.findOption(50);
    testing.expect(opt3.number == 50);
    const exp3: []const u8 = &[_]u8{1};
    testing.expect(std.mem.eql(u8, exp3, opt3.value));

    // Attempting to access the second option should result in usage error
    testing.expectError(error.InvalidArgument, req.findOption(23));

    // Skipping options and accessing payload should work.
    testing.expectError(error.ZeroLengthPayload, req.skipOptions());
}
