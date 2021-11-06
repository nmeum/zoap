const std = @import("std");
const testing = std.testing;

const buffer = @import("buffer.zig");
const codes = @import("codes.zig");
const opts = @import("opts.zig");

// CoAP version implemented by this library.
//
// From RFC 7252:
//
//  Version (Ver): 2-bit unsigned integer. Indicates the CoAP version
//  number. Implementations of this specification MUST set this field
//  to 1 (01 binary).
//
const VERSION: u2 = 1;

// Maximum length of a CoAP token.
//
// From RFC 7252:
//
//  Lengths 9-15 are reserved, MUST NOT be sent, and MUST be processed
//  as a message format error.
//
const MAX_TOKEN_LEN = 8;

// CoAP Payload marker.
//
// From RFC 7252:
//
//  If present and of non-zero length, it is prefixed by a fixed,
//  one-byte Payload Marker (0xFF), which indicates the end of options
//  and the start of the payload.
//
const OPTION_END = 0xff;

// CoAP message type.
//
// From RFC 7252:
//
//  2-bit unsigned integer. Indicates if this message is of type
//  Confirmable (0), Non-confirmable (1), Acknowledgement (2), or Reset
//  (3).
//
pub const Msg = enum(u2) {
    con = 0, // Confirmable
    non = 1, // Non-confirmable
    ack = 2, // Acknowledgement
    rst = 3, // Reset
};

pub const Header = packed struct {
    token_len: u4,
    type: Msg,
    version: u2,
    code: codes.Code,
    message_id: u16,
};

/// Implements delta encoding for the CoAP option format.
const DeltaEncoding = union(enum) {
    noExt: u4,
    extByte: u8,
    extHalf: u16,

    fn encode(val: u32) DeltaEncoding {
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

    /// Identifier for nibbles in the first CoAP option byte.
    fn id(self: DeltaEncoding) u4 {
        switch (self) {
            DeltaEncoding.noExt => |x| return x,
            DeltaEncoding.extByte => return 13,
            DeltaEncoding.extHalf => return 14,
        }
    }

    /// Amount of additionall extension bytes (0-2 bytes)
    /// required to store this value (not including the initial ID
    /// byte in the option format).
    fn size(self: DeltaEncoding) usize {
        return switch (self) {
            DeltaEncoding.noExt => 0,
            DeltaEncoding.extByte => 1,
            DeltaEncoding.extHalf => 2,
        };
    }

    /// Write extension bytes (0-2 bytes) to the given WriteBuffer
    /// with safety-checked undefined behaviour.
    fn writeExtend(self: DeltaEncoding, wb: *buffer.WriteBuffer) void {
        switch (self) {
            DeltaEncoding.noExt => {},
            DeltaEncoding.extByte => |x| wb.byte(x),
            DeltaEncoding.extHalf => |x| wb.half(x),
        }
    }
};

pub const Response = struct {
    header: Header,
    token: []const u8,
    buffer: buffer.WriteBuffer,
    last_option: u32 = 0,
    zero_payload: bool = true,

    const WriteError = error{BufTooSmall};
    const PayloadWriter = std.io.Writer(*Response, WriteError, write);

    pub fn init(buf: []u8, mt: Msg, code: codes.Code, token: []const u8, id: u16) !Response {
        if (buf.len < @sizeOf(Header) + token.len)
            return error.BufTooSmall;
        if (token.len > MAX_TOKEN_LEN)
            return error.InvalidTokenLength;

        var hdr = Header{
            .version = VERSION,
            .type = mt,
            .token_len = @intCast(u4, token.len),
            .code = code,
            .message_id = id,
        };

        var r = Response{
            .header = hdr,
            .token = token,
            .buffer = .{ .slice = buf },
        };

        hdr.message_id = std.mem.nativeToBig(u16, hdr.message_id);
        const serialized = @bitCast(u32, hdr);

        r.buffer.word(serialized);
        r.buffer.bytes(token);

        return r;
    }

    pub fn reply(buf: []u8, req: *const Request, mt: Msg, code: codes.Code) !Response {
        const hdr = req.header;
        return init(buf, mt, code, req.token, hdr.message_id);
    }

    /// Add an option to the CoAP response. Options must be added in the
    /// in order of their Option Numbers. After data has been written to
    /// the payload, no additional options can be added. Both invariants
    /// are enforced using assertions in Debug and ReleaseSafe modes.
    pub fn addOption(self: *Response, opt: *const opts.Option) !void {
        // This function cannot be called after payload has been written.
        std.debug.assert(self.zero_payload);

        std.debug.assert(self.last_option <= opt.number);
        const delta = opt.number - self.last_option;

        const odelta = DeltaEncoding.encode(delta);
        const olen = DeltaEncoding.encode(@intCast(u32, opt.value.len));

        const reqcap = 1 + odelta.size() + olen.size() + opt.value.len;
        if (self.buffer.capacity() < reqcap)
            return error.BufTooSmall;

        // See https://datatracker.ietf.org/doc/html/rfc7252#section-3.1
        self.buffer.byte(@as(u8, odelta.id()) << 4 | olen.id());
        odelta.writeExtend(&self.buffer);
        olen.writeExtend(&self.buffer);
        self.buffer.bytes(opt.value);

        self.last_option = opt.number;
    }

    /// Write data to the payload of the CoAP response. If the given data
    /// exceeds the available space in the buffer, an error is returned.
    fn write(self: *Response, data: []const u8) WriteError!usize {
        var len = data.len;
        if (self.zero_payload)
            len += 1;

        // This function is part of the public API, thus safety-checked
        // undefined behavior is not good enough and we add a bounds check.
        if (self.buffer.capacity() < len)
            return WriteError.BufTooSmall;

        if (self.zero_payload) {
            self.buffer.byte(OPTION_END);
            self.zero_payload = false;
        }

        self.buffer.bytes(data);
        return data.len; // Don't return len to not confuse caller.
    }

    /// Update CoAP response code after creating the packet.
    pub fn setCode(self: *Response, code: codes.Code) void {
        // Code is *always* the second byte in the buffer.
        self.buffer.slice[1] = @bitCast(u8, code);
    }

    pub fn payloadWriter(self: *Response) PayloadWriter {
        return PayloadWriter{ .context = self };
    }

    pub fn marshal(self: *Response) []u8 {
        return self.buffer.serialized();
    }
};

test "test header serialization" {
    const exp = @embedFile("../testvectors/basic-header.bin");

    var buf = [_]u8{0} ** exp.len;
    var resp = try Response.init(&buf, Msg.con, codes.GET, &[_]u8{}, 2342);

    const serialized = resp.marshal();
    try testing.expect(std.mem.eql(u8, serialized, exp));
}

test "test setCode after package creation" {
    const exp = @embedFile("../testvectors/basic-header.bin");

    var buf = [_]u8{0} ** exp.len;
    var resp = try Response.init(&buf, Msg.con, codes.DELETE, &[_]u8{}, 2342);

    // Change code from DELETE to GET. The latter is expected.
    resp.setCode(codes.GET);

    const serialized = resp.marshal();
    try testing.expect(std.mem.eql(u8, serialized, exp));
}

test "test header serialization with token" {
    const exp = @embedFile("../testvectors/with-token.bin");

    var buf = [_]u8{0} ** exp.len;
    var resp = try Response.init(&buf, Msg.ack, codes.PUT, &[_]u8{ 23, 42 }, 5);

    const serialized = resp.marshal();
    try testing.expect(std.mem.eql(u8, serialized, exp));
}

test "test header serialization with insufficient buffer space" {
    const exp: []const u8 = &[_]u8{ 0, 0, 0 };
    var buf = [_]u8{0} ** exp.len;

    // Given buffer is large enough to contain header, but one byte too
    // small too contain the given token, thus an error should be raised.
    try testing.expectError(error.BufTooSmall, Response.init(&buf, Msg.ack, codes.PUT, &[_]u8{23}, 5));

    // Ensure that Response.init has no side effects.
    try testing.expect(std.mem.eql(u8, &buf, exp));
}

test "test payload serialization" {
    const exp = @embedFile("../testvectors/with-payload.bin");

    var buf = [_]u8{0} ** exp.len;
    var resp = try Response.init(&buf, Msg.rst, codes.DELETE, &[_]u8{}, 1);

    var w = resp.payloadWriter();
    try w.print("Hello", .{});

    const serialized = resp.marshal();
    try testing.expect(std.mem.eql(u8, serialized, exp));
}

test "test option serialization" {
    const exp = @embedFile("../testvectors/with-options.bin");

    var buf = [_]u8{0} ** exp.len;
    var resp = try Response.init(&buf, Msg.con, codes.GET, &[_]u8{}, 2342);

    // Zero byte extension
    const opt0 = opts.Option{ .number = 2, .value = &[_]u8{0xff} };
    try resp.addOption(&opt0);

    // One byte extension
    const opt1 = opts.Option{ .number = 23, .value = &[_]u8{ 13, 37 } };
    try resp.addOption(&opt1);

    // Two byte extension
    const opt2 = opts.Option{ .number = 65535, .value = &[_]u8{} };
    try resp.addOption(&opt2);

    // Two byte extension (not enough space in buffer)
    const opt_err = opts.Option{ .number = 65535, .value = &[_]u8{} };
    try testing.expectError(error.BufTooSmall, resp.addOption(&opt_err));

    const serialized = resp.marshal();
    try testing.expect(std.mem.eql(u8, serialized, exp));
}

pub const Request = struct {
    header: Header,
    slice: buffer.ReadBuffer,
    token: []const u8,
    payload: ?([]const u8),
    last_option: ?opts.Option,

    pub fn init(buf: []const u8) !Request {
        var slice = buffer.ReadBuffer{ .slice = buf };
        if (buf.len < @sizeOf(Header))
            return error.FormatError;

        // Cast first four bytes to u32 and convert them to header struct
        const serialized: u32 = try slice.word();
        var hdr = @bitCast(Header, serialized);

        // Convert message_id to a integer in host byteorder
        hdr.message_id = std.mem.bigToNative(u16, hdr.message_id);

        var token: []const u8 = &[_]u8{};
        if (hdr.token_len > 0) {
            if (hdr.token_len > MAX_TOKEN_LEN)
                return error.FormatError;

            token = slice.bytes(hdr.token_len) catch {
                return error.FormatError;
            };
        }

        // For the first instance in a message, a preceding
        // option instance with Option Number zero is assumed.
        const init_option = opts.Option{ .number = 0, .value = &[_]u8{} };

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

    /// Returns the next option or null if the packet contains a payload
    /// and the option end has been reached. If the packet does not
    /// contain a payload an error is returned.
    ///
    /// Options are returned in the order of their Option Numbers.
    fn nextOption(self: *Request) !?opts.Option {
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
                self.payload = self.slice.remaining();
            }
            return null;
        }

        const delta = try self.decodeValue(@intCast(u4, option >> 4));
        const len = try self.decodeValue(@intCast(u4, option & 0xf));

        var optnum = self.last_option.?.number + delta;
        var optval = self.slice.bytes(len) catch {
            return error.FormatError;
        };

        const ret = opts.Option{
            .number = optnum,
            .value = optval,
        };

        self.last_option = ret;
        return ret;
    }

    /// Find an option with the given Option Number in the CoAP packet.
    /// It is an error if an option with the given Option Number does
    /// not exist. After this function has been called (even if an error
    /// was returned) it is no longer possible to retrieve options with
    /// a smaller Option Number then the given one. Similarly, when
    /// attempting to find multiple options, this function must be
    /// called in order of their Option Numbers.
    pub fn findOption(self: *Request, optnum: u32) !opts.Option {
        if (optnum == 0)
            return error.InvalidArgument;
        if (self.last_option == null)
            return error.EndOfOptions;

        const n = self.last_option.?.number;
        if (n > 0 and n >= optnum)
            return error.InvalidArgument; // XXX: Use assert instead?

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

    /// Skip all remain options in the CoAP packet and return a pointer
    /// to the package payload (if any). After this function has been
    /// called it is no longer possible to extract options from the packet.
    pub fn extractPayload(self: *Request) !(?[]const u8) {
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

        std.debug.assert(self.last_option == null);
        return self.payload;
    }
};

test "test header parser" {
    const buf = @embedFile("../testvectors/with-token.bin");
    const req = try Request.init(buf);
    const hdr = req.header;

    try testing.expect(hdr.version == VERSION);
    try testing.expect(hdr.type == Msg.ack);
    try testing.expect(hdr.token_len == 2);
    try testing.expect(req.token[0] == 23);
    try testing.expect(req.token[1] == 42);
    try testing.expect(hdr.code.equal(codes.PUT));
    try testing.expect(hdr.message_id == 5);
}

test "test payload parsing" {
    const buf = @embedFile("../testvectors/with-payload.bin");
    var req = try Request.init(buf);

    const payload = try req.extractPayload();
    try testing.expect(std.mem.eql(u8, payload.?, "Hello"));
}

test "test nextOption without payload" {
    const buf = @embedFile("../testvectors/with-options.bin");
    var req = try Request.init(buf);

    const opt1_opt = try req.nextOption();
    const opt1 = opt1_opt.?;

    try testing.expect(opt1.number == 2);
    try testing.expect(std.mem.eql(u8, opt1.value, &[_]u8{0xff}));

    const opt2_opt = try req.nextOption();
    const opt2 = opt2_opt.?;

    try testing.expect(opt2.number == 23);
    try testing.expect(std.mem.eql(u8, opt2.value, &[_]u8{ 13, 37 }));

    const opt3_opt = try req.nextOption();
    const opt3 = opt3_opt.?;

    try testing.expect(opt3.number == 65535);
    try testing.expect(std.mem.eql(u8, opt3.value, &[_]u8{}));

    // No payload marker → expect error.
    try testing.expectError(error.EndOfStream, req.nextOption());
}

test "test nextOption with payload" {
    const buf = @embedFile("../testvectors/payload-and-options.bin");
    var req = try Request.init(buf);

    const next_opt = try req.nextOption();
    const opt = next_opt.?;

    try testing.expect(opt.number == 0);
    try testing.expect(std.mem.eql(u8, opt.value, "test"));

    // Payload marker → expect null.
    const last_opt = try req.nextOption();
    try testing.expect(last_opt == null);

    // Running nextOption again must return null again.
    const last_opt_again = try req.nextOption();
    try testing.expect(last_opt_again == null);

    // Extracting payload must work.
    const payload = try req.extractPayload();
    try testing.expect(std.mem.eql(u8, payload.?, "foobar"));
}

test "test findOption without payload" {
    const buf = @embedFile("../testvectors/with-options.bin");
    var req = try Request.init(buf);

    // First option
    const opt1 = try req.findOption(2);
    try testing.expect(opt1.number == 2);
    const exp1: []const u8 = &[_]u8{0xff};
    try testing.expect(std.mem.eql(u8, exp1, opt1.value));

    // Third option, skipping second
    const opt3 = try req.findOption(65535);
    try testing.expect(opt3.number == 65535);
    const exp3: []const u8 = &[_]u8{};
    try testing.expect(std.mem.eql(u8, exp3, opt3.value));

    // Attempting to access the second option should result in usage error
    try testing.expectError(error.InvalidArgument, req.findOption(23));

    // Skipping options and accessing payload should work
    // but return an error since this packet has no payload.
    try testing.expectError(error.ZeroLengthPayload, req.extractPayload());
}
