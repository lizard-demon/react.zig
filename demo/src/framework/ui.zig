const std = @import("std");

// --- Data Structures ---

pub const Dir = enum(u1) { h, v };
pub const Align = enum(u2) { start, center, end };

pub const Layout = struct {
    // Output
    x: f32 = 0, y: f32 = 0, w: f32 = 0, h: f32 = 0,

    // Input
    sw: f32 = 0, sh: f32 = 0, 
    dir: Dir = .h, ax: Align = .start, ay: Align = .start,
    pad: u16 = 0, gap: u16 = 0,

    // Interaction State
    hover: bool = false,
    click: bool = false, 
    pressed: bool = false, 
};

// --- Systems ---

pub fn update(root: anytype, mouse_x: f32, mouse_y: f32, mouse_down: bool) ?*anyopaque {
    if (!comptime reflect.hasLayout(@TypeOf(root.*))) return null;
    
    solve(root);

    var ctx = InputContext{ .x = mouse_x, .y = mouse_y, .down = mouse_down, .clicked_ptr = null };
    interact(root, &ctx);

    return ctx.clicked_ptr;
}

pub fn visit(root: anytype, ctx: anytype, func: anytype) void {
    const T = @TypeOf(root.*);
    if (comptime reflect.hasLayout(T)) func(ctx, root);

    inline for (std.meta.fields(T)) |f| {
        if (!std.mem.eql(u8, f.name, "layout")) {
            const field = &@field(root, f.name);
            if (comptime reflect.hasLayout(@TypeOf(field.*))) {
                visit(field, ctx, func);
            }
        }
    }
}

// --- Internal Implementation ---

const InputContext = struct {
    x: f32, y: f32, down: bool,
    clicked_ptr: ?*anyopaque,
};

fn interact(node: anytype, ctx: *InputContext) void {
    const T = @TypeOf(node.*);
    const l = &node.layout;

    l.click = false;
    l.hover = false;
    
    const hit = (ctx.x >= l.x and ctx.x <= l.x + l.w and ctx.y >= l.y and ctx.y <= l.y + l.h);
    
    var child_captured = false;
    const fields = std.meta.fields(T);
    
    inline for (0..fields.len) |i| {
        const f = fields[fields.len - 1 - i]; 
        if (!std.mem.eql(u8, f.name, "layout")) {
            const child = &@field(node, f.name);
            if (comptime reflect.hasLayout(@TypeOf(child.*))) {
                if (!child_captured) {
                    interact(child, ctx);
                    if (child.layout.hover or child.layout.pressed) child_captured = true;
                } else {
                     clearFlags(child);
                }
            }
        }
    }

    if (!child_captured and hit) {
        l.hover = true;
        if (ctx.down) {
            l.pressed = true;
        } else if (l.pressed) {
            l.pressed = false;
            l.click = true;
            ctx.clicked_ptr = @ptrCast(node);
        }
    } else if (!hit) {
        l.hover = false;
        l.pressed = false;
    }
}

fn clearFlags(node: anytype) void {
    node.layout.hover = false;
    node.layout.pressed = false;
    node.layout.click = false;
    inline for (std.meta.fields(@TypeOf(node.*))) |f| {
        if (!std.mem.eql(u8, f.name, "layout")) {
            const child = &@field(node, f.name);
            if (comptime reflect.hasLayout(@TypeOf(child.*))) clearFlags(child);
        }
    }
}

fn solve(root: anytype) void {
    var buf: [256]Layout = undefined;
    var n: usize = 0;
    reflect.collect(root, &buf, &n);
    if (n == 0) return;
    
    const p = &@field(root, "layout");
    flex.size(p, buf[0..n], 0);
    flex.size(p, buf[0..n], 1);
    flex.pos(p, buf[0..n]);
    
    n = 0;
    reflect.write(root, &buf, &n);
    reflect.recurse(root, solve);
}

const reflect = struct {
    fn hasLayout(comptime T: type) bool {
        return @typeInfo(T) == .@"struct" and @hasField(T, "layout") and @TypeOf(@field(@as(T, undefined), "layout")) == Layout;
    }
    fn collect(val: anytype, buf: []Layout, idx: *usize) void {
        inline for (@typeInfo(@TypeOf(val.*)).@"struct".fields) |f| {
            if (!std.mem.eql(u8, f.name, "layout") and comptime hasLayout(f.type)) {
                buf[idx.*] = @field(val, f.name).layout;
                idx.* += 1;
            }
        }
    }
    fn write(val: anytype, buf: []Layout, idx: *usize) void {
        inline for (@typeInfo(@TypeOf(val.*)).@"struct".fields) |f| {
            if (!std.mem.eql(u8, f.name, "layout") and comptime hasLayout(f.type)) {
                @field(val, f.name).layout = buf[idx.*];
                idx.* += 1;
            }
        }
    }
    fn recurse(val: anytype, action: anytype) void {
        inline for (@typeInfo(@TypeOf(val.*)).@"struct".fields) |f| {
            if (!std.mem.eql(u8, f.name, "layout") and comptime hasLayout(f.type)) {
                action(&@field(val, f.name));
            }
        }
    }
};

const flex = struct {
    fn size(p: *Layout, k: []Layout, ax: u1) void {
        const along = @intFromEnum(p.dir) == ax;
        const pd = @as(f32, @floatFromInt(p.pad * 2));
        const avail = (if (ax == 0) p.w else p.h) - pd;
        var dim: [256]f32 = undefined;
        var grow: f32 = 0;
        
        for (k, 0..) |*c, i| {
            const sz = if (ax == 0) c.sw else c.sh;
            if (sz < 0) { 
                grow += -sz; 
                dim[i] = 0; 
            } else if (sz > 0) { 
                dim[i] = sz; 
            } else { 
                dim[i] = if (ax == 0) c.w else c.h; 
            }
        }
        
        var used: f32 = 0;
        for (dim[0..k.len]) |v| used = if (along) used + v else @max(used, v);
        if (along) used += @floatFromInt(p.gap * @as(u16, @intCast(if (k.len>0) k.len-1 else 0)));
        
        if (along and grow > 0 and avail > used) {
            const unit = (avail - used) / grow;
            for (k, 0..) |*c, i| {
                const sz = if (ax == 0) c.sw else c.sh;
                if (sz < 0) dim[i] = unit * -sz;
            }
        }

        // FIX: Moved assignment inside the loop block
        for (k, 0..) |*c, i| {
            if (ax == 0) {
                c.w = dim[i];
            } else {
                c.h = dim[i];
            }
        }
    }

    fn pos(p: *Layout, k: []Layout) void {
        const dir = @intFromEnum(p.dir);
        const pd = @as(f32, @floatFromInt(p.pad));
        const gap = @as(f32, @floatFromInt(p.gap));
        var off: @Vector(2, f32) = .{ p.x + pd, p.y + pd };
        for (k) |*c| {
            c.x = off[0]; c.y = off[1];
            off[dir] += (if (dir==0) c.w else c.h) + gap;
        }
    }
};
