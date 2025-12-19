const std = @import("std");

pub const Color = struct { r: u8, g: u8, b: u8, a: u8 };

pub const Command = union(enum) {
    rect: struct { x: f32, y: f32, w: f32, h: f32, color: Color },
    text: struct { x: f32, y: f32, str: []const u8, color: Color },
};

pub const Canvas = struct {
    // Switching to Unmanaged to handle the allocator explicitly 
    // and resolve the 'member function expected 2 arguments' errors.
    commands: std.ArrayListUnmanaged(Command) = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Canvas {
        return .{
            .allocator = allocator,
            .commands = .{},
        };
    }

    pub fn deinit(self: *Canvas) void {
        self.commands.deinit(self.allocator);
    }

    pub fn clear(self: *Canvas) void {
        self.commands.clearRetainingCapacity();
    }

    pub fn rect(self: *Canvas, x: f32, y: f32, w: f32, h: f32, color: Color) void {
        self.commands.append(self.allocator, .{ 
            .rect = .{ .x = x, .y = y, .w = w, .h = h, .color = color } 
        }) catch unreachable;
    }

    pub fn text(self: *Canvas, x: f32, y: f32, str: []const u8, color: Color) void {
        self.commands.append(self.allocator, .{ 
            .text = .{ .x = x, .y = y, .str = str, .color = color } 
        }) catch unreachable;
    }

    pub fn items(self: *const Canvas) []Command {
        return self.commands.items;
    }
};
