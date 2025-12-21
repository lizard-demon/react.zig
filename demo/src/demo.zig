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

// --- 2. State Definition ---

const Actions = enum { None, Click };
const MyBtn = Button(Actions); 

const AppState = struct {
    layout: zui.Layout = .{ .w=600, .h=400, .pad=20, .gap=20 },
    
    // Logic State
    action: Actions = .None,
    stage_a: i32 = 0,
    stage_b: i32 = 0,
    stage_c: i32 = 0,

    main: struct {
        layout: zui.Layout = .{ .sw=-1, .sh=-1, .pad=10, .gap=10 },
        trigger: MyBtn = .{ .label = "TRIGGER CHAIN", .action = .Click },
    } = .{},
};

const Context = struct {
    gfx: zui.List,
    input: zui.Input = .{},
};

// --- 3. Logic (The Reactor) ---

const Logic = struct {
    // Comptime key allows us to perform tree-shaking on logic branches
    pub fn react(proxy: anytype, comptime key: anytype) void {
        switch (key) {
            .action => {
                if (proxy.get(.action) == .Click) {
                    std.debug.print("1. [Action] Triggered.\n", .{});
                    proxy.emit(.stage_a, 1);
                }
            },
            .stage_a => {
                std.debug.print("2. [Chain] Stage A active. Emitting B...\n", .{});
                proxy.emit(.stage_b, 1);
            },
            .stage_b => {
                std.debug.print("3. [Chain] Stage B active. Emitting C...\n", .{});
                proxy.emit(.stage_c, 1);
            },
            .stage_c => {
                std.debug.print("4. [Chain] Stage C active. Chain Complete.\n", .{});
                // Uncomment to test safety:
                // proxy.emit(.stage_a, 2); 
            },
            else => {},
        }
    }
};

// --- 4. Main Loop ---

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    var app = zui.Store(AppState, Logic, Context){ .ctx = .{ .gfx = zui.List.init(gpa.allocator()) } };
    defer app.ctx.gfx.deinit();

    app.emit(.layout, .{ .w=600, .h=400, .dir=.v, .pad=20 });

    const input_log = [_]struct{x: f32, y:f32, d: bool}{
        .{ .x=40, .y=40, .d=false },
        .{ .x=40, .y=40, .d=true },  
        .{ .x=40, .y=40, .d=false }, 
    };

    std.debug.print("\n--- Recursive DAG Demo ---\n", .{});
    
    var frame: usize = 0;
    var idx: usize = 0;

    while (frame < 20) : (frame += 1) {
        if (frame % 5 == 0 and idx < input_log.len) {
            const in = input_log[idx];
            app.ctx.input = .{ .x=in.x, .y=in.y, .down=in.d, .active=app.ctx.input.down };
            idx += 1;
        }

        if (app.dirty) {
            zui.solve(&app.state);
            app.handle(); 
            
            app.ctx.gfx.clear();
            zui.render(&app.state, &app.ctx.gfx);
            app.dirty = false;
            
            std.debug.print("Rendered Frame {d} (Vtx: {d})\n", .{frame, app.ctx.gfx.vtx.items.len});
        }
        
        var i: usize = 0; while(i<10_000_000):(i+=1){std.mem.doNotOptimizeAway(i);}
    }
    std.debug.print("\n", .{});
}
