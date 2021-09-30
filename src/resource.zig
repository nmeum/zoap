const std = @import("std");
const pkt = @import("packet.zig");
const opt = @import("options.zig");

// TODO: Allow returning an error
pub const ResourceHandler = fn (packet: *pkt.Packet) void;

pub const Resource = struct {
    path: []const u8,
    handler: ResourceHandler,

    pub fn matchPath(self: Resource, path: []const u8) bool {
        return std.mem.eql(u8, self.path, path);
    }
};

pub const Dispatcher = struct {
    resources: []const Resource,

    pub fn dispatch(self: Dispatcher, packet: *pkt.Packet) !bool {
        const path_opt = try packet.findOption(opt.URIPath);
        const path = path_opt.value;

        for (self.resources) |res, _| {
            if (!res.matchPath(path))
                continue;

            res.handler(packet);
            return true;
        }

        return false;
    }
};
