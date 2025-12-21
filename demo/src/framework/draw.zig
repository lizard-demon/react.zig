const std = @import("std");

pub const Color = struct { r: u8, g: u8, b: u8, a: u8 = 255 };

/// Universal primitives that any renderer (GPU or CPU) should support.
pub const Primitive = union(enum) {
    /// Draw a filled rectangle
    rect: struct { x: f32, y: f32, w: f32, h: f32, color: Color },
    /// Draw a texture/image (referenced by ID)
    image: struct { x: f32, y: f32, w: f32, h: f32, id: usize },
    /// Draw text string
    text: struct { x: f32, y: f32, str: []const u8, color: Color },
    /// Define a clipping region (for scrolling/windows)
    scissor: struct { x: f32, y: f32, w: f32, h: f32 },
};

/// The Command Buffer.
/// This is what your logic populates, and what your renderer consumes.
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

    // --- Builder API ---

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
    
    pub fn pushScissor(self: *List, x: f32, y: f32, w: f32, h: f32) void {
        self.cmd_buffer.append(self.allocator, .{ 
            .scissor = .{ .x=x, .y=y, .w=w, .h=h } 
        }) catch {};
    }
};
