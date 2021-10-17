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
