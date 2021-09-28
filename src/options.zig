pub const Option = struct {
    number: u32,
    value: []const u8,
};

// https://datatracker.ietf.org/doc/html/rfc7252#section-5.10
pub const IfMatch: u32 = 1;
pub const URIHost: u32 = 3;
pub const URIPath: u32 = 11;
