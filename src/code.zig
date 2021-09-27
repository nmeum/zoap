pub const Code = packed struct {
    detail: u5,
    class: u3,

    pub fn equal(self: Code, other: Code) bool {
        return self.class == other.class and self.detail == other.detail;
    }
};

// See https://datatracker.ietf.org/doc/html/rfc7252#section-12.1

// Requests
pub const GET = Code{ .class = 0, .detail = 01 };
pub const POST = Code{ .class = 0, .detail = 02 };
pub const PUT = Code{ .class = 0, .detail = 03 };
pub const DELETE = Code{ .class = 0, .detail = 04 };
