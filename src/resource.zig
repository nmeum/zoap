const std = @import("std");
const pkt = @import("packet.zig");
const opt = @import("options.zig");

// TODO: Allow returning an error
pub const ResourceHandler = fn (req: *pkt.Request) void;

pub const Resource = struct {
    path: []const u8,
    handler: ResourceHandler,

    pub fn matchPath(self: Resource, path: []const u8) bool {
        return std.mem.eql(u8, self.path, path);
    }
};

pub const Dispatcher = struct {
    resources: []const Resource,

    pub fn dispatch(self: Dispatcher, req: *pkt.Request) !bool {
        const path_opt = try req.findOption(opt.URIPath);
        const path = path_opt.value;

        for (self.resources) |res, _| {
            if (!res.matchPath(path))
                continue;

            res.handler(req);
            return true;
        }

        return false;
    }
};
