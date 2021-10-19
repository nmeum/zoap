const mem = @import("std").mem;

pub const WriteBuffer = struct {
    slice: []u8,
    pos: usize = 0,

    pub fn byte(self: *WriteBuffer, b: u8) !void {
        if (self.slice.len - self.pos < @sizeOf(u8))
            return error.OutOfBounds;

        self.slice[self.pos] = b;
        self.pos += @sizeOf(u8);
    }

    pub fn half(self: *WriteBuffer, h: u16) !void {
        if (self.slice.len - self.pos < @sizeOf(u16))
            return error.OutOfBounds;

        mem.copy(u8, self.slice[self.pos..], mem.asBytes(&h));
        self.pos += @sizeOf(u16);
    }

    pub fn word(self: *WriteBuffer, w: u32) !void {
        if (self.slice.len - self.pos < @sizeOf(u32))
            return error.OutOfBounds;

        mem.copy(u8, self.slice[self.pos..], mem.asBytes(&w));
        self.pos += @sizeOf(u32);
    }

    pub fn bytes(self: *WriteBuffer, buf: []const u8) !void {
        if (self.slice.len - self.pos < buf.len)
            return error.OutOfBounds;

        mem.copy(u8, self.slice[self.pos..], buf);
        self.pos += buf.len;
    }
};

pub const ReadBuffer = struct {
    slice: []const u8,

    pub fn byte(self: *ReadBuffer) !u8 {
        if (self.slice.len < @sizeOf(u8))
            return error.OutOfBounds;

        const result = self.slice[0];
        self.slice = self.slice[@sizeOf(u8)..];
        return result;
    }

    pub fn half(self: *ReadBuffer) !u16 {
        if (self.slice.len < @sizeOf(u16))
            return error.OutOfBounds;

        const result = self.slice[0..@sizeOf(u16)].*;
        self.slice = self.slice[@sizeOf(u16)..];
        return @bitCast(u16, result);
    }

    pub fn word(self: *ReadBuffer) !u32 {
        if (self.slice.len < @sizeOf(u32))
            return error.OutOfBounds;

        const result = self.slice[0..@sizeOf(u32)].*;
        self.slice = self.slice[@sizeOf(u32)..];
        return @bitCast(u32, result);
    }

    pub fn ptr(self: *ReadBuffer) !(*const u8) {
        if (self.slice.len < 1)
            return error.OutOfBounds;

        return &self.slice[0];
    }

    pub fn bytes(self: *ReadBuffer, numBytes: usize) !([]const u8) {
        if (self.slice.len < numBytes)
            return error.OutOfBounds;

        const result = self.slice[0..numBytes];
        self.slice = self.slice[numBytes..];
        return result;
    }

    pub fn length(self: *ReadBuffer) usize {
        return self.slice.len;
    }
};
