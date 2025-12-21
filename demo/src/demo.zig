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

const Actions = enum { None, Click };
const MyBtn = Button(Actions); 

const AppData = struct {
    layout: zui.Layout = .{ .w=600, .h=400, .pad=20, .gap=20 },
    action: Actions = .None,
    val: i32 = 0,
    main: struct {
        layout: zui.Layout = .{ .sw=-1, .sh=-1, .pad=10, .gap=10 },
        trigger: MyBtn = .{ .label = "CLICK ME", .action = .Click },
    } = .{},
};

const Context = struct {
    gfx: zui.List,
    input: zui.Input = .{},
};

const Logic = struct {
    pub fn react(flow: anytype, comptime field: anytype) void {
        switch (field) {
            .action => {
                if (flow.data.action == .Click) {
                    flow.emit(.val, flow.data.val + 1);
                }
            },
            .val => {
                std.debug.print("Value is now: {d}\n", .{flow.data.val});
            },
            else => {},
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    // Store is now generic. It doesn't know about zui.handle()
    var app = zui.Store(AppData, Logic, Context){ .ctx = .{ .gfx = zui.List.init(gpa.allocator()) } };
    defer app.ctx.gfx.deinit();

    app.emit(.layout, .{ .w=600, .h=400, .dir=.v, .pad=20 });

    const input_log = [_]struct{x: f32, y:f32, d: bool}{
        .{ .x=40, .y=40, .d=false },
        .{ .x=40, .y=40, .d=true },  
        .{ .x=40, .y=40, .d=false }, 
    };

    std.debug.print("\n--- Decoupled DAG Demo ---\n", .{});
    
    var frame: usize = 0;
    var idx: usize = 0;

    while (frame < 20) : (frame += 1) {
        // 1. Update Input
        if (frame % 5 == 0 and idx < input_log.len) {
            const in = input_log[idx];
            app.ctx.input = .{ .x=in.x, .y=in.y, .down=in.d, .active=app.ctx.input.down };
            idx += 1;
        }

        if (app.dirty) {
            // 2. Run Systems Manually (Decoupled)
            zui.solve(&app.data);                     // Calculate Layout
            zui.handle(&app.data, &app, &app.ctx);    // Process Input Interactions
            
            // 3. Render
            app.ctx.gfx.clear();
            zui.render(&app.data, &app.ctx.gfx);
            app.dirty = false;
            
            std.debug.print("Frame {d}: Rendered {d} Verts\n", .{frame, app.ctx.gfx.vtx.items.len});
        }
        
        var i: usize = 0; while(i<10_000_000):(i+=1){std.mem.doNotOptimizeAway(i);}
    }
    std.debug.print("\n", .{});
}
