const std = @import("std");
const react = @import("react");
const layout_engine = @import("layout.zig");

// --- 1. Bridge ---

pub const LayoutContext = struct {
    pub fn react(self: *@This(), state: anytype) void {
        _ = self;
        // Trigger the external layout algorithm
        layout_engine.layout(state);
        
        std.debug.print("\x1b[32m[Layout Calculated]\x1b[0m\n", .{});
        dump(state, 0);
    }

    fn dump(scope: anytype, depth: usize) void {
        const T = @TypeOf(scope.*);
        const w = scope.widget;
        for (0..depth) |_| std.debug.print("  ", .{});
        std.debug.print("{s}: {d:.0}x{d:.0} @ ({d:.0}, {d:.0})\n", .{ @typeName(T), w.w, w.h, w.x, w.y });

        inline for (std.meta.fields(T)) |f| {
            if (!std.mem.eql(u8, f.name, "widget")) {
                const field = &@field(scope, f.name);
                // Use the same detection logic as layout.zig
                if (@typeInfo(@TypeOf(field.*)) == .@"struct" and @hasField(@TypeOf(field.*), "widget")) {
                    dump(field, depth + 1);
                }
            }
        }
    }
};

// --- 2. UI Components ---

const Header = struct { 
    widget: layout_engine.Widget = .{ .h = 50, .sw = -1 } 
};

const Sidebar = struct { 
    widget: layout_engine.Widget = .{ .w = 200, .sh = -1 } 
};

const MainContent = struct { 
    widget: layout_engine.Widget = .{ .sw = -1, .sh = -1 } 
};

// --- 3. App State ---

pub const AppState = struct {
    // Root container (Vertical stack)
    widget: layout_engine.Widget = .{ .w = 800, .h = 600, .dir = .v, .gap = 2 },
    header: Header = .{},
    body: struct {
        // Nested container (Horizontal stack)
        widget: layout_engine.Widget = .{ .sw = -1, .sh = -1, .dir = .h, .gap = 2 },
        side: Sidebar = .{},
        content: MainContent = .{},
    } = .{},

    pub fn react(ui: anytype, comptime field: std.meta.FieldEnum(AppState)) void {
        _ = ui; _ = field;
    }
};

pub fn main() !void {
    var app = react.Framework(AppState, LayoutContext){ .ctx = .{} };
    
    // Initial layout
    app.set(.widget, app.get(.widget));

    // Dynamic update: Shrink the header
    std.debug.print("\n--- Updating Header ---\n", .{});
    var h = app.get(.header);
    h.widget.h = 30;
    app.set(.header, h);
}
