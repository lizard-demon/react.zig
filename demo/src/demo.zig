const std = @import("std");
const zui = @import("zui.zig");

// --- Components ---

const Button = struct {
    layout: zui.Layout = .{ .w = 100, .sh = -1 },
    label: []const u8 = "Btn",
    color: zui.Color = .{ .r=60, .g=60, .b=65 },

    pub fn draw(self: *const @This(), list: *zui.List) void {
        var c = self.color;
        if (self.layout.pressed) { c = .{ .r=200, .g=50, .b=50 }; }
        else if (self.layout.hover) { c.r += 30; c.g += 30; c.b += 30; }
        
        const l = self.layout;
        list.rect(l.x, l.y, l.w, l.h, c);
        list.text(l.x+10, l.y+(l.h/2), self.label, .{ .r=255, .g=255, .b=255 });
    }
};

const Panel = struct {
    layout: zui.Layout = .{ .sw=-1, .sh=-1, .pad=5, .gap=5 },
    color: zui.Color = .{ .r=30, .g=30, .b=30 },
    ok: Button = .{ .label = "OK", .color = .{ .r=40, .g=80, .b=40 } },
    cancel: Button = .{ .label = "Cancel" },
};

const AppState = struct {
    layout: zui.Layout = .{ .w=800, .h=600, .pad=10 }, 
    main: Panel = .{},
};

const Context = struct {
    gfx: zui.List,
    mouse: struct { x: f32, y: f32, down: bool } = .{ .x=0, .y=0, .down=false },
};

// --- Logic ---

const Logic = struct {
    pub fn route(e: anytype) void {
        // 1. Core Update (Layout + Input)
        const hit = zui.update(&e.sys.state, e.ctx.mouse.x, e.ctx.mouse.y, e.ctx.mouse.down);

        // 2. Logic
        if (hit) |ptr| {
            if (ptr == @as(*anyopaque, @ptrCast(&e.sys.state.main.ok))) {
                std.debug.print(">> OK Clicked!\n", .{});
            }
        }

        // 3. Render
        e.ctx.gfx.clear();
        zui.render(&e.sys.state, &e.ctx.gfx);

        // 4. Debug Output
        std.debug.print("\rDraw Cmds: {d} | Mouse: {d:.0},{d:.0}  ", .{e.ctx.gfx.cmd.items.len, e.ctx.mouse.x, e.ctx.mouse.y});
    }
};

// --- Entry ---

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    var app = zui.Router(AppState, Logic, Context){ .ctx = .{ .gfx = zui.List.init(gpa.allocator()) } };
    defer app.ctx.gfx.deinit();

    app.set(.layout, .{ .w=800, .h=600, .dir=.v, .pad=20 });

    // Interactive Loop Simulation
    const steps = [_]struct{x: f32, y:f32, d: bool}{
        .{ .x=50, .y=50, .d=false }, // Hover
        .{ .x=50, .y=50, .d=true },  // Press
        .{ .x=50, .y=50, .d=false }, // Release (Click!)
    };

    for (steps) |s| {
        // Simple busy loop wait
        var i: usize = 0;
        while (i < 50_000_000) : (i += 1) { std.mem.doNotOptimizeAway(i); }

        app.ctx.mouse = .{ .x=s.x, .y=s.y, .down=s.d };
        app.set(.layout, app.state.layout); // Force update
    }
    std.debug.print("\n", .{});
}
