const std = @import("std");
const format_util = @import("format.zig");

pub const Volume = struct {
    format: []const u8,
    format_muted: []const u8,
    sink: []const u8,
    interval_secs: u64,
    color: c_ulong,

    pub fn init(
        format: []const u8,
        format_muted: []const u8,
        sink: []const u8,
        interval_secs: u64,
        color: c_ulong,
    ) Volume {
        return .{
            .format = format,
            .format_muted = format_muted,
            .sink = if (sink.len > 0) sink else "@DEFAULT_SINK@",
            .interval_secs = interval_secs,
            .color = color,
        };
    }

    pub fn content(self: *Volume, io: std.Io, gpa: std.mem.Allocator, buffer: []u8) []const u8 {
        if (self.isMuted(io, gpa)) {
            return format_util.substitute(self.format_muted, "", buffer);
        }
        const percent = self.readVolume(io, gpa) orelse return buffer[0..0];
        var pct_buf: [8]u8 = undefined;
        const pct_str = std.fmt.bufPrint(&pct_buf, "{d}", .{percent}) catch return buffer[0..0];
        return format_util.substitute(self.format, pct_str, buffer);
    }

    fn isMuted(self: *Volume, io: std.Io, gpa: std.mem.Allocator) bool {
        const result = std.process.run(gpa, io, .{
            .argv = &.{ "pactl", "get-sink-mute", self.sink },
        }) catch return false;
        defer gpa.free(result.stdout);
        defer gpa.free(result.stderr);
        // Output: "Mute: yes" or "Mute: no"
        return std.mem.indexOf(u8, result.stdout, "yes") != null;
    }

    fn readVolume(self: *Volume, io: std.Io, gpa: std.mem.Allocator) ?u32 {
        const result = std.process.run(gpa, io, .{
            .argv = &.{ "pactl", "get-sink-volume", self.sink },
        }) catch return null;
        defer gpa.free(result.stdout);
        defer gpa.free(result.stderr);
        // Output (one line): "Volume: front-left: 19661 /  30% / -24.61 dB ..."
        // Strategy: find the first '%' and walk back to the start of the number.
        const out = result.stdout;
        const pct_idx = std.mem.indexOfScalar(u8, out, '%') orelse return null;
        var start = pct_idx;
        while (start > 0) {
            const ch = out[start - 1];
            if (ch >= '0' and ch <= '9') {
                start -= 1;
            } else break;
        }
        if (start == pct_idx) return null;
        return std.fmt.parseInt(u32, out[start..pct_idx], 10) catch null;
    }

    pub fn interval(self: *Volume) u64 {
        return self.interval_secs;
    }

    pub fn getColor(self: *Volume) c_ulong {
        return self.color;
    }
};
