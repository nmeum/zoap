pub const Code = packed struct {
    detail: u5,
    class: u3,

    pub fn equal(self: Code, other: Code) bool {
        return self.class == other.class and self.detail == other.detail;
    }
};

// See https://datatracker.ietf.org/doc/html/rfc7252#section-12.1

// Requests
pub const GET = Code{ .class = 0, .detail = 1 };
pub const POST = Code{ .class = 0, .detail = 2 };
pub const PUT = Code{ .class = 0, .detail = 3 };
pub const DELETE = Code{ .class = 0, .detail = 4 };

// Responses
pub const CREATED = Code{ .class = 2, .detail = 1 };
pub const DELETED = Code{ .class = 2, .detail = 2 };
pub const VALID = Code{ .class = 2, .detail = 3 };
pub const CHANGED = Code{ .class = 2, .detail = 4 };
pub const CONTENT = Code{ .class = 2, .detail = 5 };
//
pub const BAD_REQ = Code{ .class = 4, .detail = 0 };
pub const UNAUTH = Code{ .class = 4, .detail = 1 };
pub const BAD_OPT = Code{ .class = 4, .detail = 2 };
pub const FORBIDDEN = Code{ .class = 4, .detail = 3 };
pub const NOT_FOUND = Code{ .class = 4, .detail = 4 };
pub const BAD_METHOD = Code{ .class = 4, .detail = 5 };
pub const NOT_ACCEPT = Code{ .class = 4, .detail = 6 };
//
pub const NOT_IMPL = Code{ .class = 5, .detail = 1 };
pub const INTERNAL_ERR = Code{ .class = 5, .detail = 0 };
