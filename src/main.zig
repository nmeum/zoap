const std = @import("std");
const testing = std.testing;
const codes = @import("code.zig");

// CoAP version implemented by this library.
//
// From RFC 7252:
//
//  Version (Ver): 2-bit unsigned integer. Indicates the CoAP version
//  number. Implementations of this specification MUST set this field
//  to 1 (01 binary).
//
pub const Version: u2 = 1;

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

pub const Option = struct {
    number: u32,
    value: []const u8,
};

const Buffer = struct {
    slice: []const u8,

    pub fn get_u8(self: *Buffer) !u8 {
        if (self.slice.len < @sizeOf(u8))
            return error.OutOfBounds;

        const result = self.slice[0];
        self.slice = self.slice[@sizeOf(u8)..];
        return result;
    }

    pub fn get_u16(self: *Buffer) !u16 {
        if (self.slice.len < @sizeOf(u16))
            return error.OutOfBounds;

        const result = self.slice[0..@sizeOf(u16)].*;
        self.slice = self.slice[@sizeOf(u16)..];
        return @bitCast(u16, result);
    }

    pub fn get_u32(self: *Buffer) !u32 {
        if (self.slice.len < @sizeOf(u32))
            return error.OutOfBounds;

        const result = self.slice[0..@sizeOf(u32)].*;
        self.slice = self.slice[@sizeOf(u32)..];
        return @bitCast(u32, result);
    }

    pub fn get_ptr(self: *Buffer) !(*const u8) {
        if (self.slice.len < 1)
            return error.OutOfBounds;

        return &self.slice[0];
    }

    pub fn get_bytes(self: *Buffer, numBytes: usize) !([]const u8) {
        if (self.slice.len < numBytes)
            return error.OutOfBounds;

        const result = self.slice[0..numBytes];
        self.slice = self.slice[numBytes..];
        return result;
    }

    pub fn length(self: *Buffer) usize {
        return self.slice.len;
    }
};

pub const Parser = struct {
    header: Header,
    slice: Buffer,
    token: ?[]const u8,
    payload: ?*const u8,
    last_option: ?Option,

    const MAX_TOKEN_LEN = 8;
    const OPTION_END = 0xff;

    pub fn init(buf: []const u8) !Parser {
        var slice = Buffer{.slice = buf};
        if (buf.len < @sizeOf(Header))
            return error.FormatError;

        // Cast first four bytes to u32 and convert them to header struct
        const firstByte = slice.slice[0]; // XXX (see below)
        const serialized: u32 = try slice.get_u32();
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

            token = slice.get_bytes(hdr.token_len) catch { return error.FormatError; };
        }

        // For the first instance in a message, a preceding
        // option instance with Option Number zero is assumed.
        const init_option = Option{.number = 0, .value = &[_]u8{}};

        return Parser{
            .header      = hdr,
            .token       = token,
            .slice       = slice,
            .payload     = null,
            .last_option = init_option,
        };
    }

    // https://datatracker.ietf.org/doc/html/rfc7252#section-3.1
    fn decode_value(self: *Parser, val: u8) !u16 {
        switch (val) {
            13 => {
                // From RFC 7252:
                //
                //  13: An 8-bit unsigned integer follows the initial byte and
                //  indicates the Option Delta minus 13.
                //
                const result = self.slice.get_u8() catch { return error.FormatError; };
                return @as(u16, result + 13);
            },
            14 => {
                // From RFC 7252:
                //
                //  14: A 16-bit unsigned integer in network byte order follows the
                //  initial byte and indicates the Option Delta minus 269.
                //
                const result = self.slice.get_u16() catch { return error.FormatError; };
                return std.mem.bigToNative(u16, result) + 269;
            },
            15 => {
                return error.PayloadMarker;
            },
            else => {
                return val;
            },
        }
    }

    // TODO: Comptime to enforce order of functions calls (e.g. no next_option after skip_options)

    fn next_option(self: *Parser) !?Option {
        if (self.last_option == null)
            return null;

        const option = self.slice.get_u8() catch { return error.EndOfStream; };
        if (option == OPTION_END) {
            self.last_option = null;
            if (self.slice.length() < 1) {
                // For zero-length payload OPTION_END should not be set.
                return error.InvalidPayload;
            } else {
                self.payload = try self.slice.get_ptr();
            }
            return null;
        }

        const delta = try self.decode_value(option >> 4);
        const len = try self.decode_value(option & 0xf);

        var optnum = self.last_option.?.number + delta;
        var optval = self.slice.get_bytes(len) catch { return error.FormatError; };

        const ret = Option{
            .number = optnum,
            .value  = optval,
        };
        self.last_option = ret;
        return ret;
    }

    pub fn find_option(self: *Parser, optnum: u32) !Option {
        if (optnum == 0)
            return error.InvalidArgument;
        if (self.last_option == null)
            return error.EndOfOptions;

        const n = self.last_option.?.number;
        if (n > 0 and n >= optnum)
            return error.InvalidArgument;

        while (true) {
            const next = try self.next_option();
            if (next == null) {
                return error.EndOfOptions;
            }

            const opt = next.?;
            if (opt.number == optnum) {
                return opt;
            } else if (opt.number > optnum) {
                return error.OptionNotFound;
            }
        }
    }

    pub fn skip_options(self: *Parser) !void {
        while (true) {
            var opt = self.next_option() catch |err| {
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
    const buf: []const u8 = &[_]u8{0x41, 0x01, 0x09, 0x26, 0x17};
    const par = try Parser.init(buf);
    const hdr = par.header;

    testing.expect(hdr.version == Version);
    testing.expect(hdr.type == Mtype.confirmable);
    testing.expect(hdr.token_len == 1);
    testing.expect(par.token.?[0] == 23);
    testing.expect(hdr.code.equal(codes.GET));
    testing.expect(hdr.message_id == 2342);
}

test "test payload parsing" {
    const buf: []const u8 = &[_]u8{0x62, 0x03, 0x04, 0xd2, 0xdd, 0x64, 0xff, 0x17, 0x2a, 0x0d, 0x25};
    var par = try Parser.init(buf);

    try par.skip_options();
    testing.expect(par.payload.? == &buf[7]);
}

test "test option parser" {
    const buf: []const u8 = &[_]u8{0x41, 0x01, 0x09, 0x26, 0x17, 0xd2, 0x0a, 0x0d, 0x25};
    var par = try Parser.init(buf);

    const next_opt = try par.next_option();
    const opt = next_opt.?;
    const val = opt.value;

    testing.expect(opt.number == 23);
    testing.expect(val.len == 2);
    testing.expect(val[0] == 13);
    testing.expect(val[1] == 37);
}

test "test find_option" {
    const buf: []const u8 = &[_]u8{0x51, 0x01, 0x30, 0x39, 0x05, 0xd4, 0x0a, 0x01, 0x02, 0x03, 0x04, 0xd1, 0x06, 0x17, 0x81, 0x01};
    var par = try Parser.init(buf);

    // First option
    const opt1 = try par.find_option(23);
    testing.expect(opt1.number == 23);
    const exp1: []const u8 = &[_]u8{1, 2, 3, 4};
    testing.expect(std.mem.eql(u8, exp1, opt1.value));

    // Third option, skipping second
    const opt3 = try par.find_option(50);
    testing.expect(opt3.number == 50);
    const exp3: []const u8 = &[_]u8{1};
    testing.expect(std.mem.eql(u8, exp3, opt3.value));

    // Attempting to access the second option should result in usage error
    testing.expectError(error.InvalidArgument, par.find_option(23));

    // Skipping options and accessing payload should work.
    testing.expectError(error.ZeroLengthPayload, par.skip_options());
}
