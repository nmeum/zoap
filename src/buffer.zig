const mem = @import("std").mem;

/// WriteBuffer adds support allows writing bytes to an underlying buffer
/// with safety-checked undefined behaviour. That is, the caller should
/// check in advance whether sufficient space is available via
/// WriteBuffer.capacity().
pub const WriteBuffer = struct {
    slice: []u8,
    pos: usize = 0,

    pub fn serialized(self: *WriteBuffer) []u8 {
        return self.slice[0..self.pos];
    }

    pub fn capacity(self: *WriteBuffer) usize {
        return self.slice.len - self.pos;
    }

    pub fn bytes(self: *WriteBuffer, buf: []const u8) void {
        // mem.copy does provide us with safety-checked
        // undefined behaviour. Thus we don't need to check
        // the capacity explicitly here.
        @memcpy(self.slice[self.pos .. self.pos + buf.len], buf);
        self.pos += buf.len;
    }

    fn write(self: *WriteBuffer, ptr: anytype) void {
        self.bytes(mem.asBytes(ptr));
    }

    pub fn byte(self: *WriteBuffer, b: u8) void {
        self.write(&b);
    }

    pub fn half(self: *WriteBuffer, h: u16) void {
        self.write(&h);
    }

    pub fn word(self: *WriteBuffer, w: u32) void {
        self.write(&w);
    }
};

pub const ReadBuffer = struct {
    slice: []const u8,

    pub fn length(self: *ReadBuffer) usize {
        return self.slice.len;
    }

    pub fn remaining(self: *ReadBuffer) []const u8 {
        return self.slice;
    }

    pub fn bytes(self: *ReadBuffer, numBytes: usize) !([]const u8) {
        if (self.slice.len < numBytes)
            return error.OutOfBounds;

        const result = self.slice[0..numBytes];
        self.slice = self.slice[numBytes..];
        return result;
    }

    fn read(self: *ReadBuffer, comptime T: type, dest: anytype) !void {
        const slice = try self.bytes(@sizeOf(T));
        dest.* = @bitCast(slice[0..@sizeOf(T)].*);
    }

    pub fn byte(self: *ReadBuffer) !u8 {
        var r: u8 = undefined;
        try self.read(u8, &r);
        return r;
    }

    pub fn half(self: *ReadBuffer) !u16 {
        var r: u16 = undefined;
        try self.read(u16, &r);
        return r;
    }

    pub fn word(self: *ReadBuffer) !u32 {
        var r: u32 = undefined;
        try self.read(u32, &r);
        return r;
    }
};
