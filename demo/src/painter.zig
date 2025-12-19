const std = @import("std");
const L = @import("layout.zig");
const Draw = @import("react").Draw;

pub fn paint(canvas: *Draw.Canvas, scope: anytype) void {
    const T = @TypeOf(scope.*);
    
    // 1. If this struct has a widget, "draw" its background
    if (@hasField(T, "widget")) {
        const w = scope.widget;
        // Subtle Pikestyle aesthetic: Slate background with a thin highlight
        canvas.rect(w.x, w.y, w.w, w.h, .{ .r = 45, .g = 45, .b = 50, .a = 255 });
        canvas.rect(w.x + 1, w.y + 1, w.w - 2, w.h - 2, .{ .r = 30, .g = 30, .b = 35, .a = 255 });
    }

    // 2. Reflectively walk children to paint the tree
    inline for (std.meta.fields(T)) |f| {
        if (!std.mem.eql(u8, f.name, "widget")) {
            const field = &@field(scope, f.name);
            const FieldT = @TypeOf(field.*);

            if (@typeInfo(FieldT) == .@"struct" and @hasField(FieldT, "widget")) {
                paint(canvas, field);
            }
        }
    }
}
