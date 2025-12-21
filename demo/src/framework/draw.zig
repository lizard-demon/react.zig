const std = @import("std");
const ui = @import("ui.zig");

pub const Color = struct { r: u8, g: u8, b: u8, a: u8 = 255 };

pub const Primitive = union(enum) {
    rect: struct { x: f32, y: f32, w: f32, h: f32, color: Color },
    text: struct { x: f32, y: f32, str: []const u8, color: Color },
    scissor: struct { x: f32, y: f32, w: f32, h: f32 },
};

pub const List = struct {
    cmd_buffer: std.ArrayListUnmanaged(Primitive) = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) List {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *List) void {
        self.cmd_buffer.deinit(self.allocator);
    }

    pub fn clear(self: *List) void {
        self.cmd_buffer.clearRetainingCapacity();
    }

    // --- Primitives ---

    pub fn pushRect(self: *List, x: f32, y: f32, w: f32, h: f32, color: Color) void {
        self.cmd_buffer.append(self.allocator, .{ 
            .rect = .{ .x=x, .y=y, .w=w, .h=h, .color=color } 
        }) catch {};
    }

    pub fn pushText(self: *List, x: f32, y: f32, str: []const u8, color: Color) void {
        self.cmd_buffer.append(self.allocator, .{ 
            .text = .{ .x=x, .y=y, .str=str, .color=color } 
        }) catch {};
    }
};

// --- THE GENERIC GLUE ---

/// The Universal Visitor Function.
/// Pass this to ui.visit() to render any tree.
pub fn submit(ctx: *List, node: anytype) void {
    const T = @TypeOf(node.*);

    // Rule 1: Custom Behavior (Self-Contained Response)
    // If the widget defines 'draw', let it handle everything (hover, click visuals).
    if (@hasDecl(T, "draw")) {
        node.draw(ctx);
        return;
    }

    // Rule 2: Default Behavior (Data-Driven)
    // If no custom draw logic, just render the data we see.
    const l = node.layout;
    
    // Auto-draw background
    if (@hasField(T, "color")) {
        ctx.pushRect(l.x, l.y, l.w, l.h, node.color);
    }
    
    // Auto-draw text
    if (@hasField(T, "label")) {
        // Simple centering
        ctx.pushText(l.x + 5, l.y + (l.h/2), node.label, .{ .r=255, .g=255, .b=255 });
    }
}
