const std = @import("std");

// --- 1. Graphics Backend ---

pub const Color = u32;
pub const Vertex = extern struct { pos: [2]f32, uv: [2]f32, col: Color };
pub const DrawCmd = struct { elem_count: u32, clip_rect: [4]f32, texture_id: ?*anyopaque };

pub const List = struct {
    vtx: std.ArrayListUnmanaged(Vertex) = .{},
    idx: std.ArrayListUnmanaged(u16) = .{},
    cmd: std.ArrayListUnmanaged(DrawCmd) = .{},
    alloc: std.mem.Allocator,
    clip: [4]f32 = .{ -1e4, -1e4, 2e4, 2e4 },
    tex: ?*anyopaque = null,

    pub fn init(a: std.mem.Allocator) List { return .{ .alloc = a }; }
    pub fn deinit(l: *List) void { l.vtx.deinit(l.alloc); l.idx.deinit(l.alloc); l.cmd.deinit(l.alloc); }
    
    pub fn clear(l: *List) void {
        l.vtx.clearRetainingCapacity(); l.idx.clearRetainingCapacity(); l.cmd.clearRetainingCapacity();
        l.cmd.append(l.alloc, .{ .elem_count=0, .clip_rect=l.clip, .texture_id=l.tex }) catch {};
    }

    pub fn rect(l: *List, x: f32, y: f32, w: f32, h: f32, c: Color) void {
        l.reserve(4, 6);
        const i = @as(u16, @intCast(l.vtx.items.len));
        l.pushVtx(x, y, 0, 0, c); l.pushVtx(x+w, y, 0, 0, c);
        l.pushVtx(x+w, y+h, 0, 0, c); l.pushVtx(x, y+h, 0, 0, c);
        l.pushIdx(i); l.pushIdx(i+1); l.pushIdx(i+2); l.pushIdx(i); l.pushIdx(i+2); l.pushIdx(i+3);
    }

    pub fn text(l: *List, x: f32, y: f32, str: []const u8, c: Color) void {
        var cx = x;
        for (str) |char| {
            if (char == ' ') { cx += 4; continue; }
            l.rect(cx, y-5, 5, 8, c); cx += 6;
        }
    }

    pub fn cursor(l: *List, x: f32, y: f32, c: Color) void {
        l.reserve(3, 3);
        const i = @as(u16, @intCast(l.vtx.items.len));
        l.pushVtx(x, y, 0, 0, c); l.pushVtx(x, y+15, 0, 0, c); l.pushVtx(x+10, y+10, 0, 0, c);
        l.pushIdx(i); l.pushIdx(i+1); l.pushIdx(i+2);
    }

    pub fn pack(r: u8, g: u8, b: u8, a: u8) Color {
        return @as(u32, a)<<24 | @as(u32, b)<<16 | @as(u32, g)<<8 | @as(u32, r);
    }

    fn reserve(l: *List, v: usize, i: usize) void {
        l.vtx.ensureUnusedCapacity(l.alloc, v) catch {}; l.idx.ensureUnusedCapacity(l.alloc, i) catch {};
    }
    fn pushVtx(l: *List, x: f32, y: f32, u: f32, v: f32, c: Color) void {
        l.vtx.appendAssumeCapacity(.{ .pos = .{x, y}, .uv = .{u, v}, .col = c });
    }
    fn pushIdx(l: *List, i: u16) void {
        l.idx.appendAssumeCapacity(i);
        l.cmd.items[l.cmd.items.len-1].elem_count += 1;
    }
};

// --- 2. Input & Layout Primitives ---

pub const Input = struct {
    x: f32 = 0, y: f32 = 0, down: bool = false,
    active: bool = false,
};

pub const Layout = struct {
    x: f32 = 0, y: f32 = 0, w: f32 = 0, h: f32 = 0,
    sw: f32 = 0, sh: f32 = 0,
    dir: enum(u1) { h, v } = .h, pad: u16 = 0, gap: u16 = 0,
    hover: bool = false, pressed: bool = false,
};

// --- 3. Recursive DAG Store ---

pub fn Store(comptime State: type, comptime Logic: type, comptime Ctx: type) type {
    return struct {
        const Self = @This();
        const Key = std.meta.FieldEnum(State);
        state: State = .{},
        ctx: Ctx,
        dirty: bool = true,

        pub fn get(s: *Self, comptime k: Key) std.meta.fieldInfo(State, k).type {
            return @field(s.state, @tagName(k));
        }

        pub fn emit(s: *Self, comptime k: Key, v: std.meta.fieldInfo(State, k).type) void {
            s.update(k, v, .{});
        }

        fn update(s: *Self, comptime k: Key, v: anytype, comptime path: anytype) void {
            const ptr = &@field(s.state, @tagName(k));
            if (std.meta.eql(ptr.*, v)) return;
            
            ptr.* = v;
            s.dirty = true; // Data changed -> Needs render

            if (@hasDecl(Logic, "react")) {
                const Proxy = struct {
                    parent: *Self,
                    pub fn get(p: @This(), comptime k2: Key) std.meta.fieldInfo(State, k2).type {
                        return p.parent.get(k2);
                    }
                    pub fn emit(p: @This(), comptime k2: Key, v2: std.meta.fieldInfo(State, k2).type) void {
                        inline for (path) |prev| {
                            if (k2 == prev) @compileError("Circular Dependency: " ++ @tagName(k2));
                        }
                        p.parent.update(k2, v2, path ++ .{k2});
                    }
                };
                // Lazy-comptime instantiation of the reaction chain
                Logic.react(Proxy{ .parent = s }, k);
            }
        }

        pub fn handle(s: *Self) void {
            handleTree(&s.state, s, &s.ctx);
        }
    };
}

// --- 4. Systems ---

pub fn solve(root: anytype) void {
    if (!comptime hasLayout(@TypeOf(root.*))) return;
    
    var buf: [256]Layout = undefined;
    var n: usize = 0;
    inline for (@typeInfo(@TypeOf(root.*)).@"struct".fields) |f| {
        if (!std.mem.eql(u8, f.name, "layout") and comptime hasLayout(f.type)) {
            buf[n] = @field(root, f.name).layout; n += 1;
        }
    }
    if (n == 0) return;

    const p = &@field(root, "layout");
    flex(p, buf[0..n], 0); flex(p, buf[0..n], 1);
    
    var off: @Vector(2, f32) = .{ p.x + @as(f32,@floatFromInt(p.pad)), p.y + @as(f32,@floatFromInt(p.pad)) };
    const dir = @intFromEnum(p.dir);
    for (buf[0..n]) |*c| {
        c.x = off[0]; c.y = off[1];
        off[dir] += (if (dir==0) c.w else c.h) + @as(f32, @floatFromInt(p.gap));
    }

    n = 0;
    inline for (@typeInfo(@TypeOf(root.*)).@"struct".fields) |f| {
        if (!std.mem.eql(u8, f.name, "layout") and comptime hasLayout(f.type)) {
            @field(root, f.name).layout = buf[n]; n += 1;
            solve(&@field(root, f.name));
        }
    }
}

pub fn handleTree(root: anytype, sys: anytype, ctx: anytype) void {
    if (!comptime hasLayout(@TypeOf(root.*))) return;
    const l = &root.layout;
    const old_h = l.hover;
    const old_p = l.pressed;

    const hit = (ctx.input.x >= l.x and ctx.input.x <= l.x + l.w and ctx.input.y >= l.y and ctx.input.y <= l.y + l.h);
    var captured = false;
    
    const fields = std.meta.fields(@TypeOf(root.*));
    inline for (0..fields.len) |i| {
        const f = fields[fields.len - 1 - i];
        if (!std.mem.eql(u8, f.name, "layout")) {
            const child = &@field(root, f.name);
            if (comptime hasLayout(@TypeOf(child.*))) {
                if (!captured) {
                    handleTree(child, sys, ctx);
                    if (child.layout.hover or child.layout.pressed) captured = true;
                } else clearFlags(child, sys);
            }
        }
    }

    var new_h = false;
    var new_p = false;

    if (!captured and hit) {
        new_h = true;
        if (ctx.input.down) {
            new_p = true;
        } else if (old_p) {
            if (@hasDecl(@TypeOf(root.*), "onClick")) root.onClick(.{ .sys = sys });
        }
    }

    if (old_h != new_h or old_p != new_p) {
        l.hover = new_h;
        l.pressed = new_p;
        sys.dirty = true; // Visual state changed -> Needs render
    }
}

pub fn render(root: anytype, list: *List) void {
    visit(root, list, struct {
        fn call(l: *List, node: anytype) void {
            if (@hasDecl(@TypeOf(node.*), "draw")) {
                node.draw(l);
            } else {
                const lay = node.layout;
                if (@hasField(@TypeOf(node.*), "color")) l.rect(lay.x, lay.y, lay.w, lay.h, node.color);
                if (@hasField(@TypeOf(node.*), "label")) l.text(lay.x+5, lay.y+lay.h/2, node.label, 0xFFFFFFFF);
            }
        }
    }.call);
}

// --- Helpers ---

fn hasLayout(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasField(T, "layout") and @TypeOf(@field(@as(T, undefined), "layout")) == Layout;
}

fn visit(root: anytype, ctx: anytype, func: anytype) void {
    const T = @TypeOf(root.*);
    if (comptime hasLayout(T)) func(ctx, root);
    inline for (std.meta.fields(T)) |f| {
        if (!std.mem.eql(u8, f.name, "layout")) {
            const child = &@field(root, f.name);
            if (comptime hasLayout(@TypeOf(child.*))) visit(child, ctx, func);
        }
    }
}

fn clearFlags(node: anytype, sys: anytype) void {
    if (node.layout.hover or node.layout.pressed) {
        node.layout.hover = false; 
        node.layout.pressed = false;
        sys.dirty = true;
    }
    inline for (std.meta.fields(@TypeOf(node.*))) |f| {
        if (!std.mem.eql(u8, f.name, "layout") and comptime hasLayout(f.type)) {
            clearFlags(&@field(node, f.name), sys);
        }
    }
}

fn flex(p: *Layout, k: []Layout, ax: u1) void {
    const pd = @as(f32, @floatFromInt(p.pad * 2));
    const avail = (if (ax == 0) p.w else p.h) - pd;
    var dim: [256]f32 = undefined;
    var grow: f32 = 0;
    for (k, 0..) |*c, i| {
        const sz = if (ax == 0) c.sw else c.sh;
        if (sz < 0) { grow += -sz; dim[i] = 0; } else if (sz > 0) { dim[i] = sz; } else { dim[i] = if (ax == 0) c.w else c.h; }
    }
    var used: f32 = 0;
    const is_dir = @intFromEnum(p.dir) == ax;
    for (dim[0..k.len]) |v| used = if (is_dir) used + v else @max(used, v);
    if (is_dir) used += @floatFromInt(p.gap * @as(u16, @intCast(if (k.len>0) k.len-1 else 0)));
    if (is_dir and grow > 0 and avail > used) {
        const unit = (avail - used) / grow;
        for (k, 0..) |*c, i| { if ((if (ax == 0) c.sw else c.sh) < 0) dim[i] = unit * -(if (ax == 0) c.sw else c.sh); }
    }
    for (k, 0..) |*c, i| { if (ax == 0) c.w = dim[i] else c.h = dim[i]; }
}
