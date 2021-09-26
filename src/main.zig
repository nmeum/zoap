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
const Version: u2 = 1;

// CoAP message type.
//
// From RFC 7252:
//
//  2-bit unsigned integer. Indicates if this message is of type
//  Confirmable (0), Non-confirmable (1), Acknowledgement (2), or Reset
//  (3).
//
const Mtype = enum(u2) {
    confirmable = 0,
    non_confirmable = 1,
    acknowledgement = 2,
    reset = 3,
};

const Header = packed struct {
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

pub const Parser = struct {
    header: Header,
    slice: []const u8,
    token: ?[]const u8,
    payload: ?*const u8,
    // For the first instance in a message, a preceding
    // option instance with Option Number zero is assumed.
    option_nr: u32 = 0,

    const MAX_TOKEN_LEN = 8;
    const OPTION_END = 0xff;

    pub fn init(buf: []const u8) !Parser {
        var slice = buf;
        if (buf.len < @sizeOf(Header))
            return error.FormatError;

        // Cast first four bytes to u32 and convert them to header struct
        const serialized: u32 = @bitCast(u32, slice[0..@sizeOf(Header)].*);
        var hdr = @bitCast(Header, serialized);

        // Convert message_id to a integer in host byteorder
        hdr.message_id = std.mem.bigToNative(u16, hdr.message_id);

        // Skip header in given buffer
        slice = buf[@sizeOf(Header)..];

        // TODO: Somehow extraction of the token length does not work
        // via packed structs in Zig 0.7.1 (probably compiler bug).
        hdr.token_len = @intCast(u4, buf[0] & 0xf);

        var token: ?[]const u8 = null;
        if (hdr.token_len > 0) {
            if (hdr.token_len > slice.len or hdr.token_len > MAX_TOKEN_LEN)
                return error.FormatError;

            token = slice[0..hdr.token_len];
            slice = slice[hdr.token_len..];
        }

        return Parser{
            .header  = hdr,
            .token   = token,
            .slice   = slice,
            .payload = null,
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
                if (self.slice.len < 1)
                    return error.EndOfStream;

                const result: u8 = self.slice[0] + 13;
                self.slice = self.slice[1..];

                return @as(u16, result);
            },
            14 => {
                // From RFC 7252:
                //
                //  14: A 16-bit unsigned integer in network byte order follows the
                //  initial byte and indicates the Option Delta minus 269.
                //
                if (self.slice.len < 2)
                    return error.FormatError;

                const result: u16 = @bitCast(u16, self.slice[0..@sizeOf(u16)].*);
                self.slice = self.slice[3..];

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

    fn next_option(self: *Parser) !?Option {
        if (self.slice.len < 1)
            return error.EndOfStream;

        const option = self.slice[0];
        if (option == OPTION_END) {
            if (self.slice.len > 1)
                self.payload = &self.slice[1]; // byte after OPTION_END
            return null;
        }

        // Advance slice since decode_value access it.
        // XXX: reset slice position on decode_value error?
        self.slice = self.slice[1..];

        const delta = try self.decode_value(option >> 4);
        const len = try self.decode_value(option & 0xf);

        self.option_nr += delta;

        const value = self.slice[0..len];
        self.slice = self.slice[len..];

        return Option{
            .number = self.option_nr,
            .value  = value,
        };
    }

    fn skip_options(self: *Parser) !void {
        while (true) {
            var opt = try self.next_option();
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
