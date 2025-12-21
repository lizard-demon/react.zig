const std = @import("std");
const zui = @import("zui.zig");

// --- 1. Custom Widgets ---

// A bar that visualizes a value and changes color based on state
const Gauge = struct {
    layout: zui.Layout = .{ .w = 200, .h = 30 },
    value: u32 = 0,
    max: u32 = 120,
    label: []const u8 = "Gauge",
    color: zui.Color = zui.List.pack(50, 50, 50, 255),

    pub fn draw(self: *const @This(), list: *zui.List) void {
        const l = self.layout;
        // Draw Background
        list.rect(l.x, l.y, l.w, l.h, zui.List.pack(30, 30, 30, 255));
        
        // Draw Fill Bar
        const fill_w = (@as(f32, @floatFromInt(self.value)) / @as(f32, @floatFromInt(self.max))) * l.w;
        list.rect(l.x, l.y, fill_w, l.h, self.color);

        // Draw Text Overlay
        list.text(l.x + 10, l.y + 8, self.label, zui.List.pack(255, 255, 255, 255));
    }
};

const Button = struct {
    layout: zui.Layout = .{ .w = 100, .sh = -1 },
    label: []const u8 = "Btn",
    color: zui.Color = zui.List.pack(60, 60, 70, 255),

    pub fn draw(self: *const @This(), list: *zui.List) void {
        var c = self.color;
        if (self.layout.pressed) { c = zui.List.pack(200, 200, 200, 255); }
        else if (self.layout.hover) { c = c + 0x202020; }
        
        const l = self.layout;
        list.rect(l.x, l.y, l.w, l.h, c);
        list.text(l.x + 15, l.y + (l.h/2) - 4, self.label, 0xFFFFFFFF);
    }
};

const Panel = struct {
    layout: zui.Layout = .{ .sw=-1, .sh=-1, .pad=10, .gap=10 },
    
    // Controls
    btn_heat: Button = .{ .label = "HEAT UP", .color = zui.List.pack(150, 50, 50, 255) },
    btn_cool: Button = .{ .label = "COOL DOWN", .color = zui.List.pack(50, 50, 150, 255) },
    
    // Readouts
    gauge_heat: Gauge = .{ .label = "Core Temp", .max = 100 },
    gauge_pres: Gauge = .{ .label = "Pressure (PSI)", .max = 200 },
    
    // Status
    status_box: Button = .{ .label = "SYSTEM OK", .color = zui.List.pack(40, 100, 40, 255), .layout = .{ .w=300, .h=40 } },
};

// --- 2. Application State ---

const AppState = struct {
    layout: zui.Layout = .{ .w=800, .h=600, .pad=20, .gap=20 },
    
    // The Data Model
    heat: u32 = 0,
    pressure: u32 = 0,
    critical: bool = false,

    // The UI Tree
    main: Panel = .{},
};

const Context = struct {
    gfx: zui.List,
    mouse: struct { x: f32, y: f32, down: bool } = .{ .x=0, .y=0, .down=false },
};

// --- 3. Recursive Logic Engine ---

const Logic = struct {
    pub fn route(e: anytype) void {
        // 1. UPDATE: Run Layout & Input
        const hit = zui.update(&e.sys.state, e.ctx.mouse.x, e.ctx.mouse.y, e.ctx.mouse.down);
        
        // 2. INPUT: Map Clicks to State Changes
        if (hit) |ptr| {
            if (ptr == @as(*anyopaque, @ptrCast(&e.sys.state.main.btn_heat))) {
                // User Action: Just add heat.
                // The Logic below will recursively handle the rest.
                e.sys.emit(.heat, e.sys.state.heat + 20);
            }
            if (ptr == @as(*anyopaque, @ptrCast(&e.sys.state.main.btn_cool))) {
                if (e.sys.state.heat >= 20) e.sys.emit(.heat, e.sys.state.heat - 20);
            }
        }

        // 3. REACTIVE CHAIN (The "Recursive" Part)
        // Note: 'e.key' tells us what JUST changed.
        switch (e.key) {
            .heat => {
                std.debug.print("  [Logic] Heat changed to {d}\n", .{e.new});
                
                // Update UI Widget
                e.sys.state.main.gauge_heat.value = e.new;
                
                // Chain Reaction: Heat creates Pressure
                // emit() will call Logic.route() recursively immediately!
                e.sys.emit(.pressure, e.new * 2);
            },
            .pressure => {
                std.debug.print("    [Logic] Pressure reacted: {d}\n", .{e.new});
                
                // Update UI Widget
                e.sys.state.main.gauge_pres.value = e.new;

                // Chain Reaction: Check thresholds
                if (e.new > 160) {
                     e.sys.emit(.critical, true);
                } else {
                     e.sys.emit(.critical, false);
                }
            },
            .critical => {
                if (e.new) {
                    std.debug.print("      [Logic] CRITICAL ALERT! SCRAM!\n", .{});
                    
                    // Update UI Colors
                    e.sys.state.main.status_box.label = "DANGER: OVERLOAD";
                    e.sys.state.main.status_box.color = zui.List.pack(255, 0, 0, 255);
                    e.sys.state.main.gauge_pres.color = zui.List.pack(200, 0, 0, 255);

                    // RECURSIVE SAFETY TRIP:
                    // If we just became critical, force reset heat to 0.
                    // This will trigger .heat -> .pressure -> .critical (false)
                    if (e.old == false) { // Only trigger once on edge
                        std.debug.print("      [Logic] *** AUTOMATIC SHUTDOWN TRIGGERED ***\n", .{});
                        e.sys.emit(.heat, 0); 
                    }
                } else {
                    std.debug.print("      [Logic] System Stabilized.\n", .{});
                    e.sys.state.main.status_box.label = "SYSTEM OK";
                    e.sys.state.main.status_box.color = zui.List.pack(40, 100, 40, 255);
                    e.sys.state.main.gauge_pres.color = zui.List.pack(50, 50, 50, 255);
                }
            },
            else => {},
        }

        // 4. RENDER
        e.ctx.gfx.clear();
        zui.render(&e.sys.state, &e.ctx.gfx);
    }
};

// --- 4. Main Loop ---

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    var app = zui.Router(AppState, Logic, Context){ .ctx = .{ .gfx = zui.List.init(gpa.allocator()) } };
    defer app.ctx.gfx.deinit();

    app.emit(.layout, .{ .w=800, .h=600, .dir=.v, .pad=20 });

    std.debug.print("\n=== SYSTEM START ===\n", .{});

    // 1. Hover
    std.debug.print("\n--- User Hovers Heat ---\n", .{});
    app.ctx.mouse = .{ .x=40, .y=40, .down=false };
    app.emit(.layout, app.state.layout);

    // 2. Click (Safe)
    std.debug.print("\n--- User Clicks Heat (+20) ---\n", .{});
    app.ctx.mouse.down = true; 
    app.emit(.layout, app.state.layout); // Press
    app.ctx.mouse.down = false;
    app.emit(.layout, app.state.layout); // Release -> Trigger

    // 3. Click (Safe)
    std.debug.print("\n--- User Clicks Heat (+40) ---\n", .{});
    app.ctx.mouse.down = true; app.emit(.layout, app.state.layout);
    app.ctx.mouse.down = false; app.emit(.layout, app.state.layout);

    // 4. Click (Safe)
    std.debug.print("\n--- User Clicks Heat (+60) ---\n", .{});
    app.ctx.mouse.down = true; app.emit(.layout, app.state.layout);
    app.ctx.mouse.down = false; app.emit(.layout, app.state.layout);

    // 5. Click (Safe)
    std.debug.print("\n--- User Clicks Heat (+80) ---\n", .{});
    app.ctx.mouse.down = true; app.emit(.layout, app.state.layout);
    app.ctx.mouse.down = false; app.emit(.layout, app.state.layout);

    // 6. Click (CRITICAL!)
    // Heat becomes 100 -> Pressure 200 -> Critical TRUE -> Reset Heat 0
    std.debug.print("\n--- User Clicks Heat (+100) -> DANGER ---\n", .{});
    app.ctx.mouse.down = true; app.emit(.layout, app.state.layout);
    app.ctx.mouse.down = false; app.emit(.layout, app.state.layout);

    std.debug.print("\n=== SYSTEM END ===\n", .{});
}
