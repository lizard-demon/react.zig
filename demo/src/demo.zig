const std = @import("std");
const zui = @import("zui.zig");

// --- Components ---

const Button = struct {
    layout: zui.Layout = .{ .w = 100, .sh = -1 },
    label: []const u8 = "Btn",
    color: zui.Color = zui.List.pack(60, 60, 65, 255),

    pub fn draw(self: *const @This(), list: *zui.List) void {
        var c = self.color;
        // Simple Interaction Logic
        if (self.layout.pressed) { c = zui.List.pack(200, 50, 50, 255); }
        else if (self.layout.hover) { c = c + 0x00202020; } // Hacky lighten
        
        const l = self.layout;
        list.rect(l.x, l.y, l.w, l.h, c);
        list.text(l.x+10, l.y+(l.h/2), self.label, zui.List.pack(255,255,255,255));
    }
};

const Panel = struct {
    layout: zui.Layout = .{ .sw=-1, .sh=-1, .pad=5, .gap=5 },
    color: zui.Color = zui.List.pack(30, 30, 30, 255),
    ok: Button = .{ .label = "OK", .color = zui.List.pack(40, 80, 40, 255) },
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
        // 1. Update
        const hit = zui.update(&e.sys.state, e.ctx.mouse.x, e.ctx.mouse.y, e.ctx.mouse.down);

        if (hit) |ptr| {
            if (ptr == @as(*anyopaque, @ptrCast(&e.sys.state.main.ok))) {
                std.debug.print(">> OK Clicked!\n", .{});
            }
        }

        // 2. Render Generation
        e.ctx.gfx.clear();
        zui.render(&e.sys.state, &e.ctx.gfx);

        // 3. GPU Simulation (The "Driver")
        // In a real app, you would memcpy(gfx.vtx.items) to a GPU Buffer here.
        const gfx = &e.ctx.gfx;
        std.debug.print("\rFrame Data: {d} Verts | {d} Indices | {d} DrawCmds   ", 
            .{gfx.vtx.items.len, gfx.idx.items.len, gfx.cmd.items.len});
    }
};

// --- Entry ---

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    var app = zui.Router(AppState, Logic, Context){ .ctx = .{ .gfx = zui.List.init(gpa.allocator()) } };
    defer app.ctx.gfx.deinit();

    app.set(.layout, .{ .w=800, .h=600, .dir=.v, .pad=20 });

    const steps = [_]struct{x: f32, y:f32, d: bool}{
        .{ .x=50, .y=50, .d=false },
        .{ .x=50, .y=50, .d=true },
        .{ .x=50, .y=50, .d=false },
    };

    for (steps) |s| {
        // Busy wait
        var i: usize = 0;
        while (i < 50_000_000) : (i += 1) { std.mem.doNotOptimizeAway(i); }
        
        app.ctx.mouse = .{ .x=s.x, .y=s.y, .down=s.d };
        app.set(.layout, app.state.layout); 
    }
    std.debug.print("\n", .{});
}
