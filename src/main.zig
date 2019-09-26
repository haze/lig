const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const testing = std.testing;

const Level = enum {
    Info,
    Warn,
    Error,
    Debug,
};

const Logger = struct {
    const Self = @This();

    allocator: *mem.Allocator,
    transports: []fs.File,
    containsTty: bool,
    containsFile: bool,

    fn init(allocator: *mem.Allocator, transports: []fs.File) Self {
        var hasTty = false;
        var hasFile = false;
        for (transports) |transport| {
            const supportsAnsi = transport.supportsAnsiEscapeCodes();
            if (!hasTty and supportsAnsi) {
                hasTty = true;
            } else if (!hasFile and !supportsAnsi) {
                hasFile = true;
            }
        }
        return Logger{
            .allocator = allocator,
            .transports = transports,
            .containsTty = hasTty,
            .containsFile = hasFile,
        };
    }

    pub const RenderedLine = struct {
        prettyOutput: ?[][]const u8,
        fileOutput: ?[]const u8,
        allocator: *mem.Allocator,

        pub fn deinit(self: RenderedLine) void {
            if (self.prettyOutput) |_| {
                self.allocator.free(self.prettyOutput.?);
            }
            if (self.fileOutput) |_| {
                self.allocator.free(self.fileOutput.?);
            }
        }
    };

    fn make_line(self: *const Self, level: Level, message: []const u8) !RenderedLine {
        var prettyOutput: ?[][]const u8 = null;
        var fileOutput: ?[]const u8 = null;

        if (self.containsTty) {
            prettyOutput = [_][]const u8{};
        }

        if (self.containsFile) {
            fileOutput = try mem.dupe(self.allocator, u8, message);
        }

        return RenderedLine{
            .prettyOutput = prettyOutput,
            .fileOutput = fileOutput,
            .allocator = self.allocator,
        };
    }

    fn log(self: *const Self, level: Level, message: []const u8) !void {
        const line = try self.make_line(level, message);
        defer line.deinit();
        for (self.transports) |transport| {
            const supportsAnsi = transport.supportsAnsiEscapeCodes();
            if (supportsAnsi) {
                for (line.prettyOutput.?) |prettyLine| {
                    try transport.write(prettyLine);
                    try transport.write("\n");
                }
            } else {
                try transport.write(line.fileOutput.?);
            }
        }
    }

    pub fn safe_warn(self: *const Self, message: []const u8) !void {
        return self.log(.Warn, message);
    }
    pub fn safe_info(self: *const Self, message: []const u8) !void {
        return self.log(.Info, message);
    }
    pub fn safe_err(self: *const Self, message: []const u8) !void {
        return self.log(.Error, message);
    }
    pub fn safe_debug(self: *const Self, message: []const u8) !void {
        return self.log(.Debug, message);
    }

    pub fn info(self: *const Self, message: []const u8) void {
        self.safe_info(message) catch {};
    }
    pub fn warn(self: *const Self, message: []const u8) void {
        self.safe_warn(message) catch {};
    }
    pub fn err(self: *const Self, message: []const u8) void {
        self.safe_error(message) catch {};
    }
    pub fn debug(self: *const Self, message: []const u8) void {
        self.safe_debug(message) catch {};
    }
};

test "basic log" {
    var transports = [_]fs.File{ try std.io.getStdOut(), try fs.File.openWrite("test.log") };
    const logger = Logger.init(std.debug.global_allocator, transports[0..transports.len]);
    try logger.safe_info("hello, world");
}
