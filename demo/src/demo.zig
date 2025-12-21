const std = @import("std");
const react = @import("react");
const ui = @import("framework/ui.zig");
const draw = @import("framework/draw.zig");

// --- 1. State Definition ---

const Button = struct {
    layout: ui.Layout = .{ .w = 120, .sh = -1 }, 
    color: draw.Color = .{ .r = 200, .g = 60, .b = 60 },
    label: []const u8 = "Button",
};

const Panel = struct {
    layout: ui.Layout = .{ .sw = -1, .sh = -1, .pad = 5 }, 
    color: draw.Color = .{ .r = 40, .g = 40, .b = 45 },
    btn_submit: Button = .{ .label = "Submit" },
    btn_cancel: Button = .{ .label = "Cancel", .color = .{ .r=60, .g=60, .b=70 } },
};

const AppState = struct {
    layout: ui.Layout = .{ .w = 800, .h = 600, .pad = 10, .gap = 10 },
    main_panel: Panel = .{},
};

// --- 2. System Context ---

const Context = struct {
    commands: draw.List,
    mouse: struct { x: f32, y: f32, down: bool } = .{ .x=0, .y=0, .down=false },
};

// --- 3. Glue Logic ---

fn buildDrawList(ctx: *draw.List, node: anytype) void {
    const l = node.layout;

    // 1. Draw Background
    if (@hasField(@TypeOf(node.*), "color")) {
        var col = node.color;
        
        // AUTOMATIC INTERACTION VISUALS
        // The framework sets these flags for us!
        if (l.pressed) {
            col.r = @min(col.r + 40, 255);
            col.g = @min(col.g + 40, 255);
            col.b = @min(col.b + 40, 255);
        } else if (l.hover) {
            col.r = @min(col.r + 20, 255);
            col.g = @min(col.g + 20, 255);
            col.b = @min(col.b + 20, 255);
        }

        ctx.pushRect(l.x, l.y, l.w, l.h, col);
    }

    // 2. Draw Text
    if (@hasField(@TypeOf(node.*), "label")) {
        const text_x = l.x + 10; 
        const text_y = l.y + (l.h / 2); 
        ctx.pushText(text_x, text_y, node.label, .{ .r=255, .g=255, .b=255 });
    }
}

const AppLogic = struct {
    pub fn route(e: anytype) void {
        // A. Update Framework (Layout + Input)
        // Returns the pointer to the clicked element (if any)
        const clicked_ptr = ui.update(&e.sys.state, e.ctx.mouse.x, e.ctx.mouse.y, e.ctx.mouse.down);

        // B. Handle Interactions
        if (clicked_ptr) |ptr| {
            const p = &e.sys.state.main_panel;
            
            if (ptr == @as(*anyopaque, @ptrCast(&p.btn_submit))) {
                std.debug.print("\n\x1b[32m[SIGNAL] Submit Pressed\x1b[0m\n", .{});
            } else if (ptr == @as(*anyopaque, @ptrCast(&p.btn_cancel))) {
                std.debug.print("\n\x1b[31m[SIGNAL] Cancel Pressed\x1b[0m\n", .{});
            }
        }

        // C. Render
        e.ctx.commands.clear();
        ui.visit(&e.sys.state, &e.ctx.commands, buildDrawList);

        // Debug Output
        const cmds = e.ctx.commands.cmd_buffer.items;
        std.debug.print("\rFrame: {d} cmds | Mouse: {d:.0},{d:.0} | Down: {}   ", 
            .{cmds.len, e.ctx.mouse.x, e.ctx.mouse.y, e.ctx.mouse.down});
    }
};

// --- 4. Main ---

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var app = react.Router(AppState, AppLogic, Context){
        .ctx = .{ .commands = draw.List.init(alloc) }
    };
    defer app.ctx.commands.deinit();

    app.set(.layout, .{ .w = 800, .h = 600, .dir = .v, .pad = 20, .gap = 10 });

    // Step 1: Hover over Submit
    std.debug.print("\n--- Move Mouse to Submit ---\n", .{});
    app.ctx.mouse = .{ .x = 50, .y = 50, .down = false };
    app.set(.layout, app.state.layout);

    // Step 2: Press Down
    std.debug.print("\n--- Mouse Down ---\n", .{});
    app.ctx.mouse.down = true;
    app.set(.layout, app.state.layout);

    // Step 3: Release (Trigger Click)
    std.debug.print("\n--- Mouse Up (Click!) ---\n", .{});
    app.ctx.mouse.down = false;
    app.set(.layout, app.state.layout);
}
