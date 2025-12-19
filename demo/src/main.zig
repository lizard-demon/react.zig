const std = @import("std");
const react = @import("react");

// --- 1. Primitives ---

pub const Dir = enum { h, v };
pub const Align = enum { start, center, end };

pub const Widget = struct {
    x: f32 = 0, y: f32 = 0,
    w: f32 = 0, h: f32 = 0,
    sw: f32 = 0, // 0=fit, <0=grow(weight), >0=fixed
    sh: f32 = 0,
    dir: Dir = .v,
    pad: f32 = 0,
    gap: f32 = 0,
};

// --- 2. Layout Logic ---

pub const LayoutContext = struct {
    pub fn react(self: *@This(), state: anytype) void {
        solve(&state.widget, state);
        
        std.debug.print("\x1b[32m[Layout Solved]\x1b[0m\n", .{});
        self.dump(state, 0);
    }

    fn solve(parent: *Widget, scope: anytype) void {
        const T = @TypeOf(scope.*);
        var kids: [16]*Widget = undefined;
        var count: usize = 0;

        inline for (std.meta.fields(T)) |f| {
            if (!std.mem.eql(u8, f.name, "widget")) {
                const field = &@field(scope, f.name);
                if (@hasField(@TypeOf(field.*), "widget")) {
                    kids[count] = &field.widget;
                    count += 1;
                }
            }
        }

        if (count == 0) return;
        const slice = kids[0..count];

        applySizes(parent, slice, 0); 
        applySizes(parent, slice, 1); 
        applyPositions(parent, slice);

        inline for (std.meta.fields(T)) |f| {
            if (!std.mem.eql(u8, f.name, "widget")) {
                const field = &@field(scope, f.name);
                if (@hasField(@TypeOf(field.*), "widget")) {
                    solve(&field.widget, field);
                }
            }
        }
    }

    fn applySizes(parent: *Widget, kids: []*Widget, axis: u1) void {
        // Changed variable name 'main' to 'is_main' to avoid shadowing pub fn main
        const is_main = @intFromEnum(parent.dir) == axis;
        const avail = (if (axis == 0) parent.w else parent.h) - (parent.pad * 2);
        
        var grow_total: f32 = 0;
        for (kids) |k| {
            const stretch = if (axis == 0) k.sw else k.sh;
            if (stretch > 0) {
                if (axis == 0) k.w = stretch else k.h = stretch;
            } else if (stretch < 0) {
                grow_total += -stretch;
            } else if (!is_main) {
                if (axis == 0) k.w = avail else k.h = avail;
            }
        }

        if (is_main and grow_total > 0) {
            const unit = avail / grow_total;
            for (kids) |k| {
                const stretch = if (axis == 0) k.sw else k.sh;
                if (stretch < 0) {
                    if (axis == 0) k.w = unit * -stretch else k.h = unit * -stretch;
                }
            }
        }
    }

    fn applyPositions(parent: *Widget, kids: []*Widget) void {
        const d = @intFromEnum(parent.dir);
        var cursor: f32 = (if (d == 0) parent.x else parent.y) + parent.pad;
        const cross = (if (d == 1) parent.x else parent.y) + parent.pad;

        for (kids) |k| {
            if (d == 0) {
                k.x = cursor; k.y = cross;
                cursor += k.w + parent.gap;
            } else {
                k.x = cross; k.y = cursor;
                cursor += k.h + parent.gap;
            }
        }
    }

    fn dump(self: *const @This(), scope: anytype, depth: usize) void {
        const T = @TypeOf(scope.*);
        
        // Corrected: Access the 'widget' field of the struct for printing
        const w = scope.widget;
        for (0..depth) |_| std.debug.print("  ", .{});
        std.debug.print("{s}: {d:.0}x{d:.0} @ ({d:.0}, {d:.0})\n", .{ @typeName(T), w.w, w.h, w.x, w.y });

        inline for (std.meta.fields(T)) |f| {
            if (!std.mem.eql(u8, f.name, "widget")) {
                const field = &@field(scope, f.name);
                if (@hasField(@TypeOf(field.*), "widget")) {
                    self.dump(field, depth + 1);
                }
            }
        }
    }
};

// --- 3. App State ---

const Sidebar = struct { widget: Widget = .{ .w = 150, .sh = -1 } };
const Content = struct { widget: Widget = .{ .sw = -1, .sh = -1 } };

pub const AppState = struct {
    widget: Widget = .{ .w = 800, .h = 600, .dir = .h, .pad = 10, .gap = 5 },
    side: Sidebar = .{},
    main_view: Content = .{},

    pub fn react(ui: anytype, comptime field: std.meta.FieldEnum(AppState)) void {
        _ = ui; _ = field;
    }
};

pub fn main() !void {
    var app = react.Framework(AppState, LayoutContext){ .ctx = .{} };
    app.set(.widget, .{ .w = 1024, .h = 768, .dir = .v, .pad = 20, .gap = 10 });
}
