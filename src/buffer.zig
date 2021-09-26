pub const Buffer = struct {
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
