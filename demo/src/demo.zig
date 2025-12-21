const std = @import("std");
const zui = @import("zui.zig");

// --- Widgets ---

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

// --- App ---

const Actions = enum { None, Inc, Dec };
const MyBtn = Button(Actions); 

const AppState = struct {
    layout: zui.Layout = .{ .w=600, .h=400, .pad=20, .gap=20 },
    value: i32 = 0,
    action: Actions = .None, 
    main: struct {
        layout: zui.Layout = .{ .sw=-1, .sh=-1, .pad=10, .gap=10 },
        inc: MyBtn = .{ .label = "Increment", .action = .Inc },
        dec: MyBtn = .{ .label = "Decrement", .action = .Dec, .color = zui.List.pack(70, 40, 40, 255) },
        dsp: MyBtn = .{ .label = "Value: 0", .color = zui.List.pack(30, 30, 30, 255) },
    } = .{},
};

const Context = struct {
    gfx: zui.List,
    input: zui.Input = .{},
    render_count: usize = 0,
};

const Logic = struct {
    pub fn react(e: anytype) void {
        if (e.key == .action) {
            switch (e.new) {
                .Inc => e.sys.emit(.value, e.sys.state.value + 1),
                .Dec => e.sys.emit(.value, e.sys.state.value - 1),
                .None => {},
            }
        }
        if (e.key == .value) {
            // (Format string here in real code)
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    var app = zui.Store(AppState, Logic, Context){ .ctx = .{ .gfx = zui.List.init(gpa.allocator()) } };
    defer app.ctx.gfx.deinit();

    app.emit(.layout, .{ .w=600, .h=400, .dir=.v, .pad=20 });

    const input_log = [_]struct{x: f32, y:f32, d: bool}{
        .{ .x=40, .y=40, .d=false }, // Hover Start
        .{ .x=40, .y=40, .d=true },  // Press
        .{ .x=40, .y=40, .d=false }, // Click (Value Change)
        .{ .x=200, .y=200, .d=false}, // Move Away
    };

    std.debug.print("\n--- Retained Mode Demo ---\n", .{});
    
    var frame: usize = 0;
    var log_idx: usize = 0;

    // Simulate 60 Frames
    while (frame < 60) : (frame += 1) {
        // Inject Input (Simulate user doing stuff every 10 frames)
        if (frame % 15 == 0 and log_idx < input_log.len) {
            const in = input_log[log_idx];
            app.ctx.input = .{ .x=in.x, .y=in.y, .down=in.d, .active=app.ctx.input.down };
            log_idx += 1;
        }

        // 1. Tick: Returns TRUE if we need to redraw
        if (app.tick()) {
            app.ctx.render_count += 1;
            
            // 2. Render (Only if Dirty)
            app.ctx.gfx.clear();
            zui.render(&app.state, &app.ctx.gfx);
            app.ctx.gfx.cursor(app.ctx.input.x, app.ctx.input.y, 0xFFFF00FF);
            
            // 3. Clear Dirty
            app.dirty = false;
        }

        const g = &app.ctx.gfx;
        std.debug.print("\rFrame:{d} | Renders:{d} | Vtx:{d} | Val:{d}   ", 
            .{frame, app.ctx.render_count, g.vtx.items.len, app.state.value});

        var i: usize = 0; while(i<5_000_000):(i+=1){std.mem.doNotOptimizeAway(i);}
    }
    std.debug.print("\n", .{});
}
