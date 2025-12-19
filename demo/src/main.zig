const std = @import("std");
const react = @import("react");
const Draw = react.Draw;
const L = @import("layout.zig");
const Painter = @import("painter.zig");

// --- 1. The Layout Context ---

pub const LayoutContext = struct {
    canvas: Draw.Canvas,

    pub fn react(self: *@This(), state: anytype) void {
        // Run the external layout solver
        L.layout(state);
        
        // Rebuild the command buffer via reflection
        self.canvas.clear();
        Painter.paint(&self.canvas, state);

        // Debug report
        const cmds = self.canvas.items();
        std.debug.print("\x1b[32m[Frame Resolved]\x1b[0m {d} commands generated.\n", .{cmds.len});
        for (cmds) |cmd| {
            switch (cmd) {
                .rect => |r| std.debug.print("  Rect: {d:.0}x{d:.0} @ ({d:.0}, {d:.0})\n", .{ r.w, r.h, r.x, r.y }),
                .text => |t| std.debug.print("  Text: '{s}' @ ({d:.0}, {d:.0})\n", .{ t.str, t.x, t.y }),
            }
        }
    }
};

// --- 2. State Definition ---

const Sidebar = struct { 
    widget: L.Widget = .{ .w = 200, .sh = -1 } 
};

const Content = struct { 
    widget: L.Widget = .{ .sw = -1, .sh = -1 } 
};

pub const AppState = struct {
    widget: L.Widget = .{ .w = 1024, .h = 768, .dir = .h, .pad = 10, .gap = 5 },
    side: Sidebar = .{},
    main_view: Content = .{},

    pub fn react(ui: anytype, comptime field: std.meta.FieldEnum(AppState)) void {
        _ = ui; _ = field;
    }
};

// --- 3. Entry Point ---

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = react.Framework(AppState, LayoutContext){ 
        .ctx = .{ .canvas = Draw.Canvas.init(allocator) } 
    };
    defer app.ctx.canvas.deinit();

    // Trigger state change
    std.debug.print("Setting initial state...\n", .{});
    app.set(.widget, .{ .w = 800, .h = 600, .dir = .h, .pad = 20, .gap = 10 });
}
