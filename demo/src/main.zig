const std = @import("std");
const react = @import("react");
const L = @import("layout.zig");
const Painter = @import("painter.zig");
const Draw = react.Draw;

// --- 1. State (Data Only) ---
const Sidebar = struct { 
    widget: L.Widget = .{ .w = 200, .sh = -1 } 
};

const Content = struct { 
    widget: L.Widget = .{ .sw = -1, .sh = -1 } 
};

pub const AppState = struct {
    widget: L.Widget = .{ .w = 1024, .h = 768, .dir = .h, .pad = 10, .gap = 5 },
    side: Sidebar = .{},
    main: Content = .{},
};

// --- 2. Context (System Interface Only) ---
pub const Context = struct {
    canvas: Draw.Canvas,
};

// --- 3. Logic (The "Brain") ---
pub const AppLogic = struct {
    pub fn route(e: anytype) void {
        // 1. Solve Layout
        // We pass the raw state pointer. Layout modifies widgets in-place.
        // This is safe because these changes are computed results, not routing events.
        L.layout(&e.sys.state);

        // 2. Render
        e.ctx.canvas.clear();
        Painter.paint(&e.ctx.canvas, &e.sys.state);

        // 3. Debug Output
        const cmds = e.ctx.canvas.items();
        std.debug.print("\x1b[32m[Event: {s}]\x1b[0m {d} commands generated.\n", .{ @tagName(e.key), cmds.len });
        
        for (cmds) |cmd| {
            switch (cmd) {
                .rect => |r| std.debug.print("  Rect: {d:.0}x{d:.0} @ ({d:.0}, {d:.0})\n", .{ r.w, r.h, r.x, r.y }),
                .text => |t| std.debug.print("  Text: '{s}' @ ({d:.0}, {d:.0})\n", .{ t.str, t.x, t.y }),
            }
        }
    }
};

// --- 4. Entry ---
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize Router with Logic
    var app = react.Router(AppState, AppLogic, Context){ 
        .ctx = .{ .canvas = Draw.Canvas.init(allocator) } 
    };
    defer app.ctx.canvas.deinit();

    std.debug.print("--- Initializing ---\n", .{});
    // This triggers the router -> AppLogic.route -> Layout -> Paint
    app.set(.widget, .{ .w = 800, .h = 600, .dir = .h, .pad = 20, .gap = 10 });
}
