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

// Responses
pub const CREATED = Code{ .class = 2, .detail = 01 };
pub const BAD_REQ = Code{ .class = 4, .detail = 00 };
pub const NOT_FOUND = Code{ .class = 4, .detail = 04 };
pub const NOT_IMPL = Code{ .class = 5, .detail = 01 };
pub const INTERNAL_ERR = Code{ .class = 5, .detail = 00 };
