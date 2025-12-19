const std = @import("std");
const react = @import("react");

// --- 1. Geometric Primitives ---

pub const Dir = enum(u8) { h, v };
pub const Align = enum(u8) { start, center, end };
pub const Widget = struct {
    x: f32 = 0, y: f32 = 0,
    w: f32 = 0, h: f32 = 0,
    sw: f32 = 0, // 0=fit, <0=grow(weight), >0=fixed
    sh: f32 = 0,
    dir: Dir = .v,
    ax: Align = .start,
    ay: Align = .start,
    pad: u16 = 0,
    gap: u16 = 0,
};

// --- 2. The Layout Context ---

pub const LayoutContext = struct {
    const eps: f32 = 0.001;
    const inf: f32 = 3.4e38;

    // The Context "react" serves as the root of the layout tree.
    pub fn react(self: *@This(), state: anytype) void {
        _ = self;
        layout(state);
        
        // Final Output: Print the calculated positions
        std.debug.print("\x1b[35m[LAYOUT RESOLVED]\x1b[0m\n", .{});
        inline for (std.meta.fields(@TypeOf(state.*))) |f| {
            const val = @field(state, f.name);
            if (@typeInfo(@TypeOf(val)) == .@"struct" and @hasField(@TypeOf(val), "widget")) {
                const w = val.widget;
                std.debug.print("  {s: <8} -> pos:({d:.1}, {d:.1}) size:{d:.1}x{d:.1}\n", .{ f.name, w.x, w.y, w.w, w.h });
            }
        }
    }

    // --- Flexbox Implementation Logic ---

    fn extremes(vals: []f32, least: bool) [2]f32 {
        var e1: f32 = if (least) inf else -inf;
        var e2 = e1;
        for (vals) |v| {
            if (@abs(v - e1) < eps) continue;
            if (if (least) v < e1 else v > e1) {
                e2 = e1; e1 = v;
            } else if (if (least) v < e2 else v > e2) e2 = v;
        }
        return .{ e1, e2 };
    }

    fn distribute(vals: []*f32, limits: []f32, delta: f32, shrink: bool) void {
        var space = delta;
        var active: usize = vals.len;
        var temp: [256]f32 = undefined;
        while (@abs(space) > eps and active > 0) {
            for (vals, 0..) |v, i| temp[i] = v.*;
            const ex = extremes(temp[0..vals.len], !shrink);
            const step = if (shrink) @max(ex[1] - ex[0], space / @as(f32, @floatFromInt(active))) 
                         else @min(ex[1] - ex[0], space / @as(f32, @floatFromInt(active)));
            for (vals, limits) |v, lim| {
                if (@abs(v.* - ex[0]) < eps) {
                    const prev = v.*;
                    v.* += step;
                    if (if (shrink) v.* <= lim else v.* >= lim) { v.* = lim; active -= 1; }
                    space -= (v.* - prev);
                }
            }
        }
    }

    fn size(parent: *Widget, kids: []Widget, axis: u1) void {
        const along = @intFromEnum(parent.dir) == axis;
        const pd: f32 = @floatFromInt(parent.pad * 2);
        const gaps: f32 = if (kids.len > 1) @as(f32, @floatFromInt(parent.gap * @as(u16, @intCast(kids.len - 1)))) else 0;
        const avail = (if (axis == 0) parent.w else parent.h) - pd;

        var dims: [256]f32 = undefined;
        var grow_sum: f32 = 0;

        for (kids, 0..) |child, i| {
            const sz = if (axis == 0) child.sw else child.sh;
            const dim = if (axis == 0) child.w else child.h;
            if (sz < 0) { grow_sum += -sz; dims[i] = 0; } 
            else if (sz > 0) dims[i] = sz 
            else dims[i] = dim;
        }

        var content: f32 = 0;
        for (dims[0..kids.len]) |v| content = if (along) content + v else @max(content, v);
        if (along) content += gaps;

        const delta = avail - content;
        if (along and grow_sum > 0 and delta > eps) {
            const per_weight = delta / grow_sum;
            for (kids, 0..) |child, i| {
                const sz = if (axis == 0) child.sw else child.sh;
                if (sz < 0) dims[i] = per_weight * (-sz);
            }
        } else if (along and delta < -eps) {
            var ptrs: [256]*f32 = undefined;
            var limits: [256]f32 = undefined;
            for (0..kids.len) |i| { ptrs[i] = &dims[i]; limits[i] = 0; }
            distribute(ptrs[0..kids.len], limits[0..kids.len], delta, true);
        } else if (!along) {
            for (0..kids.len) |i| dims[i] = @min(dims[i], avail);
        }

        for (kids, 0..) |*child, i| { if (axis == 0) child.w = dims[i] else child.h = dims[i]; }
    }

    fn pos(parent: *Widget, kids: []Widget) void {
        const dir = @intFromEnum(parent.dir);
        const pd: f32 = @floatFromInt(parent.pad);
        const gap: f32 = @floatFromInt(parent.gap);

        var content: @Vector(2, f32) = @splat(0);
        for (kids) |child| {
            content[dir] += if (dir == 0) child.w else child.h;
            content[1 - dir] = @max(content[1 - dir], if (dir == 0) child.h else child.w);
        }
        if (kids.len > 0) content[dir] += gap * @as(f32, @floatFromInt(kids.len - 1));

        var off: @Vector(2, f32) = .{ parent.x + pd, parent.y + pd };
        const extra = @Vector(2, f32){parent.w, parent.h} - @as(@Vector(2, f32), @splat(pd * 2)) - content;

        const ax = if (dir == 0) parent.ax else parent.ay;
        off[dir] += switch (ax) { .center => extra[dir] / 2, .end => extra[dir], else => 0 };

        for (kids, 0..) |*child, i| {
            _ = i;
            child.x = off[0]; child.y = off[1];
            off[dir] += (if (dir == 0) child.w else child.h) + gap;
        }
    }

    fn layout(val: anytype) void {
        const T = @TypeOf(val.*);
        if (!@hasField(T, "widget")) return;

        var buf: [256]Widget = undefined;
        var n: usize = 0;

        // Collect
        inline for (std.meta.fields(T)) |f| {
            if (!std.mem.eql(u8, f.name, "widget")) {
                const field_val = @field(val, f.name);
                if (@typeInfo(@TypeOf(field_val)) == .@"struct" and @hasField(@TypeOf(field_val), "widget")) {
                    buf[n] = field_val.widget; n += 1;
                }
            }
        }
        if (n == 0) return;

        const parent = &val.widget;
        size(parent, buf[0..n], 0);
        size(parent, buf[0..n], 1);
        pos(parent, buf[0..n]);

        // Write-back
        n = 0;
        inline for (std.meta.fields(T)) |f| {
            if (!std.mem.eql(u8, f.name, "widget")) {
                if (@typeInfo(@TypeOf(@field(val, f.name))) == .@"struct" and @hasField(@TypeOf(@field(val, f.name)), "widget")) {
                    @field(val, f.name).widget = buf[n]; n += 1;
                }
            }
        }
    }
};

// --- 3. UI Implementation ---

const Header = struct {
    widget: Widget = .{ .h = 20, .sw = -1, .pad = 5 }, // grow w, fixed h
};

const Sidebar = struct {
    widget: Widget = .{ .w = 100, .sh = -1 }, // fixed w, grow h
};

pub const AppState = struct {
    widget: Widget = .{ .w = 800, .h = 600, .dir = .v, .gap = 2 }, // Root
    header: Header = .{},
    sidebar: Sidebar = .{},

    pub fn react(ui: anytype, comptime field: std.meta.FieldEnum(AppState)) void {
        _ = ui; _ = field;
    }
};

pub fn main() !void {
    var app = react.Framework(AppState, LayoutContext){ .ctx = LayoutContext{}, };

    // Mutation triggers the Flexbox Layout through LayoutContext.react
    app.set(.header, .{ .widget = .{ .h = 50, .sw = -1, .pad = 10 } });
}
