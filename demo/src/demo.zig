const std = @import("std");
const zui = @import("zui.zig");

// --- 1. Generic Widgets ---

// A generic button that emits a bound action when clicked.
// This widget is self-contained: it draws itself AND handles its own input.
pub fn Button(comptime ActionEnum: type) type {
    return struct {
        layout: zui.Layout = .{ .w = 120, .sh = -1 },
        label: []const u8 = "Btn",
        color: zui.Color = zui.List.pack(60, 60, 70, 255),
        
        // The Binding: What happens when I am clicked?
        action: ?ActionEnum = null, 

        // BEHAVIOR: Input System calls this automatically
        pub fn onClick(self: *const @This(), ctx: anytype) void {
            if (self.action) |act| {
                // Self-Emission!
                ctx.sys.emit(.action, act); 
            }
        }

        // VISUALS
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

// --- 2. Application Definition ---

const Actions = enum { None, Inc, Dec };
const MyBtn = Button(Actions); // Instantiate generic widget for our actions

const Panel = struct {
    layout: zui.Layout = .{ .sw=-1, .sh=-1, .pad=10, .gap=10 },
    
    // Declarative Bindings: We define WHAT happens right here.
    btn_inc: MyBtn = .{ .label = "Increment", .action = .Inc },
    btn_dec: MyBtn = .{ .label = "Decrement", .action = .Dec, .color = zui.List.pack(70, 40, 40, 255) },
    
    // A display button (no action)
    display: MyBtn = .{ .label = "Value: 0", .color = zui.List.pack(30, 30, 30, 255) },
};

const AppState = struct {
    layout: zui.Layout = .{ .w=600, .h=400, .pad=20, .gap=20 },
    value: i32 = 0,
    action: Actions = .None, // The generic event channel
    main: Panel = .{},
};

const Context = struct {
    gfx: zui.List,
    input: zui.Input = .{},
};

// --- 3. Logic (Pure Reactor) ---

const Logic = struct {
    pub fn react(e: anytype) void {
        // 1. INPUT ROUTING (Automatic)
        // Pass the entire System (e.sys) as context so widgets can call emit()
        zui.solve(&e.sys.state);
        zui.handle(&e.sys.state, &e.ctx.input, e); 
        
        // 2. LOGIC
        // We only react to the .action event emitted by the Buttons
        if (e.key == .action) {
            switch (e.new) {
                .Inc => e.sys.emit(.value, e.sys.state.value + 1),
                .Dec => e.sys.emit(.value, e.sys.state.value - 1),
                .None => {},
            }
        }

        // 3. UPDATES
        if (e.key == .value) {
            std.debug.print("  [Logic] Value changed to {d}\n", .{e.new});
            // Update display label (In real app use a string allocator)
        }

        // 4. RENDER
        e.ctx.gfx.clear();
        zui.render(&e.sys.state, &e.ctx.gfx);
        e.ctx.gfx.cursor(e.ctx.input.x, e.ctx.input.y, 0xFF00FFFF);

        // Update Input State for next frame (track 'active' for click detection)
        e.ctx.input.active = e.ctx.input.down;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    var app = zui.Store(AppState, Logic, Context){ .ctx = .{ .gfx = zui.List.init(gpa.allocator()) } };
    defer app.ctx.gfx.deinit();

    app.emit(.layout, .{ .w=600, .h=400, .dir=.v, .pad=20 });

    // Interactive Loop
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
        
        // Tick the engine
        app.emit(.layout, app.state.layout); 
        
        const g = &app.ctx.gfx;
        std.debug.print("\rVtx:{d} | In:{d},{d}({}) | Val:{d}   ", 
            .{g.vtx.items.len, app.ctx.input.x, app.ctx.input.y, app.ctx.input.down, app.state.value});
        
        var i: usize = 0; while(i<10_000_000):(i+=1){std.mem.doNotOptimizeAway(i);}
    }
    std.debug.print("\n", .{});
}
