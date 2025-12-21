const std = @import("std");
const zui = @import("zui.zig");

// --- 1. Generic Widgets ---

pub fn Button(comptime ActionEnum: type) type {
    return struct {
        layout: zui.Layout = .{ .w = 120, .sh = -1 },
        label: []const u8 = "Btn",
        color: zui.Color = zui.List.pack(60, 60, 70, 255),
        action: ?ActionEnum = null, 

        pub fn onClick(self: *const @This(), ctx: anytype) void {
            if (self.action) |act| ctx.sys.emit(.action, act); 
        }

        pub fn draw(self: *const @This(), list: *zui.List) void {
            var c = self.color;
            if (self.layout.pressed) c = zui.List.pack(200, 200, 200, 255)
            else if (self.layout.hover) c = c + 0x202020;
            const l = self.layout;
            list.rect(l.x, l.y, l.w, l.h, c);
            list.text(l.x+15, l.y+(l.h/2)-4, self.label, 0xFFFFFFFF);
        }
    };
}

// --- 2. Application ---

const Actions = enum { None, Inc, Dec };
const MyBtn = Button(Actions); 

const Panel = struct {
    layout: zui.Layout = .{ .sw=-1, .sh=-1, .pad=10, .gap=10 },
    btn_inc: MyBtn = .{ .label = "Increment", .action = .Inc },
    btn_dec: MyBtn = .{ .label = "Decrement", .action = .Dec, .color = zui.List.pack(70, 40, 40, 255) },
    display: MyBtn = .{ .label = "Value: 0", .color = zui.List.pack(30, 30, 30, 255) },
};

const AppState = struct {
    layout: zui.Layout = .{ .w=600, .h=400, .pad=20, .gap=20 },
    value: i32 = 0,
    action: Actions = .None, 
    main: Panel = .{},
};

const Context = struct {
    gfx: zui.List,
    input: zui.Input = .{},
};

const Logic = struct {
    pub fn react(e: anytype) void {
        zui.solve(&e.sys.state);
        zui.handle(&e.sys.state, &e.ctx.input, e); 
        
        if (e.key == .action) {
            switch (e.new) {
                .Inc => e.sys.emit(.value, e.sys.state.value + 1),
                .Dec => e.sys.emit(.value, e.sys.state.value - 1),
                .None => {},
            }
        }

        if (e.key == .value) {
            std.debug.print("  [Logic] Value changed to {d}\n", .{e.new});
        }

        e.ctx.gfx.clear();
        zui.render(&e.sys.state, &e.ctx.gfx);
        e.ctx.gfx.cursor(e.ctx.input.x, e.ctx.input.y, 0xFF00FFFF);

        e.ctx.input.active = e.ctx.input.down;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    var app = zui.Store(AppState, Logic, Context){ .ctx = .{ .gfx = zui.List.init(gpa.allocator()) } };
    defer app.ctx.gfx.deinit();

    app.emit(.layout, .{ .w=600, .h=400, .dir=.v, .pad=20 });

    const actions = [_]struct{x: f32, y:f32, d: bool}{
        .{ .x=40, .y=40, .d=false }, // Move
        .{ .x=40, .y=40, .d=true },  // Press Inc
        .{ .x=40, .y=40, .d=false }, // Click Inc
        .{ .x=40, .y=80, .d=true },  // Press Dec
        .{ .x=40, .y=80, .d=false }, // Click Dec
    };

    std.debug.print("\n--- Start ---\n", .{});
    for (actions) |a| {
        app.ctx.input.x = a.x;
        app.ctx.input.y = a.y;
        app.ctx.input.down = a.d;
        
        app.emit(.layout, app.state.layout); 
        
        const g = &app.ctx.gfx;
        std.debug.print("\rVtx:{d} | In:{d},{d}({}) | Val:{d}   ", 
            .{g.vtx.items.len, app.ctx.input.x, app.ctx.input.y, app.ctx.input.down, app.state.value});
        
        var i: usize = 0; while(i<10_000_000):(i+=1){std.mem.doNotOptimizeAway(i);}
    }
    std.debug.print("\n", .{});
}
