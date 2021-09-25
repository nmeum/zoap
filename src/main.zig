const std = @import("std");
const testing = std.testing;

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
    code: u8,
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
        slice = buf[1..];

        var token: ?[]const u8 = null;
        if (hdr.token_len > 0) {
            if (hdr.token_len > slice.len or hdr.token_len > MAX_TOKEN_LEN)
                return error.FormatError;

            token = slice[0..hdr.token_len];
            slice = slice[hdr.token_len..];
        }

        return Parser{
            .header = hdr,
            .token  = token,
            .slice  = slice,
        };
    }
};

test "test header parser" {
    const buf: []const u8 = &[_]u8{0x41, 0x01, 0x09, 0x26, 0x17};
    const par = try Parser.init(buf);
    const hdr = par.header;

    testing.expect(hdr.version == Version);
    testing.expect(hdr.type == Mtype.confirmable);
    testing.expect(hdr.token_len == 4);
    // TODO: hdr.code
    testing.expect(hdr.message_id == 2342);
}
