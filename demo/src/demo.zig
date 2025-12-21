const std = @import("std");
const react = @import("react");
const ui = @import("framework/ui.zig");
const Gfx = @import("framework/draw.zig"); // FIX: Renamed to avoid collision with 'draw()' method

// --- 1. Self-Contained Components ---

const Button = struct {
    layout: ui.Layout = .{ .w = 120, .sh = -1 }, 
    color: Gfx.Color = .{ .r = 60, .g = 60, .b = 60 }, // Uses Gfx module
    label: []const u8 = "Button",

    // This method name 'draw' previously shadowed the module 'draw'
    pub fn draw(self: *const @This(), ctx: *Gfx.List) void {
        var col = self.color;
        const l = self.layout;

        // Internal Logic
        if (l.pressed) {
            col = .{ .r = 255, .g = 100, .b = 100 }; 
        } else if (l.hover) {
            col.r += 40; col.g += 40; col.b += 40;
        }

        ctx.pushRect(l.x, l.y, l.w, l.h, col);
        ctx.pushText(l.x + 10, l.y + (l.h/2), self.label, .{ .r=255, .g=255, .b=255 });
    }
};

const Panel = struct {
    layout: ui.Layout = .{ .sw = -1, .sh = -1, .pad = 5 }, 
    color: Gfx.Color = .{ .r = 40, .g = 40, .b = 45 },
    
    // Components
    btn_submit: Button = .{ .label = "Submit", .color = .{ .r=0, .g=100, .b=0 } },
    btn_cancel: Button = .{ .label = "Cancel" },
};

const AppState = struct {
    layout: ui.Layout = .{ .w = 800, .h = 600, .pad = 10, .gap = 10 },
    main_panel: Panel = .{},
};

// --- 2. Context & Logic ---

const Context = struct {
    commands: Gfx.List,
    mouse: struct { x: f32, y: f32, down: bool } = .{ .x=0, .y=0, .down=false },
};

const AppLogic = struct {
    pub fn route(e: anytype) void {
        // A. Update (Layout + Input)
        const clicked = ui.update(&e.sys.state, e.ctx.mouse.x, e.ctx.mouse.y, e.ctx.mouse.down);

        // B. Signal Handling
        if (clicked) |ptr| {
            const p = &e.sys.state.main_panel;
            // Explicit casting for pointer comparison
            if (ptr == @as(*anyopaque, @ptrCast(&p.btn_submit))) {
                std.debug.print("\n\x1b[32m[LOGIC] Submitting Form...\x1b[0m\n", .{});
            }
        }

        // C. Render
        e.ctx.commands.clear();
        // Pass Gfx.submit as the visitor to handle the dispatch
        ui.visit(&e.sys.state, &e.ctx.commands, Gfx.submit);

        // Debug Output
        const cmds = e.ctx.commands.cmd_buffer.items;
        std.debug.print("\rFrame: {d} cmds | Mouse: {d:.0},{d:.0}   ", 
            .{cmds.len, e.ctx.mouse.x, e.ctx.mouse.y});
    }
};

// --- 3. Main ---

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var app = react.Router(AppState, AppLogic, Context){
        .ctx = .{ .commands = Gfx.List.init(alloc) }
    };
    defer app.ctx.commands.deinit();

    app.set(.layout, .{ .w = 800, .h = 600, .dir = .v, .pad = 20, .gap = 10 });

    std.debug.print("\n--- Hover Submit ---\n", .{});
    app.ctx.mouse = .{ .x = 50, .y = 50, .down = false };
    app.set(.layout, app.state.layout); 

    std.debug.print("\n--- Click Submit ---\n", .{});
    app.ctx.mouse.down = true;
    app.set(.layout, app.state.layout); 

    app.ctx.mouse.down = false;
    app.set(.layout, app.state.layout); 
}
