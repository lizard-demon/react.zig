const std   = @import("std");
const sdl3  = @import("sdl3");
const react = @import("react");

// ─── Palette ─────────────────────────────────────────────────────────────────

const ink    : sdl3.pixels.Color = .{ .r = 0,   .g = 0,   .b = 0,   .a = 255 };
const paper  : sdl3.pixels.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
const c_bg   : sdl3.pixels.Color = .{ .r = 18,  .g = 18,  .b = 22,  .a = 255 };
const c_well : sdl3.pixels.Color = .{ .r = 30,  .g = 30,  .b = 36,  .a = 255 };
const c_line : sdl3.pixels.Color = .{ .r = 46,  .g = 46,  .b = 54,  .a = 255 };
const c_dim  : sdl3.pixels.Color = .{ .r = 82,  .g = 82,  .b = 96,  .a = 255 };
const c_mute : sdl3.pixels.Color = .{ .r = 56,  .g = 56,  .b = 66,  .a = 255 };
const c_hi   : sdl3.pixels.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };

// ─── Window & Layout ─────────────────────────────────────────────────────────

const vp    : i32 = 600;
const pad   : i32 = 16;
const side  : i32 = pad + vp + pad;
const win_w : i32 = side + 200 + pad;
const win_h : i32 = pad + vp + pad;

const Page   = struct { w: i32, h: i32 };
const pages  = [_]Page{
    .{ .w = 210,  .h = 294  },
    .{ .w = 420,  .h = 588  },
    .{ .w = 630,  .h = 882  },
    .{ .w = 1050, .h = 1470 },
    .{ .w = 1470, .h = 2058 },
};
const n_pg   : i32 = pages.len;
const pg_tag = [_][:0]const u8{ "XS", "S", "M", "L", "XL" };

// ─── Tuning ──────────────────────────────────────────────────────────────────

const ring_cap : usize = 16;
const snap_cap : usize = 20;

// ─── Reactive Graph ──────────────────────────────────────────────────────────

const Ui = react.Signals(struct {
    pub const State = struct {
        page : i32 = 2,
        size : i32 = 3,
        tool : i32 = 0,
        stab : i32 = 6,
    };
    pub const compute = struct {
        pub fn cols(s: struct { page: i32 }) i32 { return pages[@intCast(s.page)].w; }
        pub fn rows(s: struct { page: i32 }) i32 { return pages[@intCast(s.page)].h; }
        pub fn scale(s: struct { cols: i32, rows: i32 }) f32 {
            return @as(f32, @floatFromInt(vp)) /
                   @as(f32, @floatFromInt(@max(s.cols, s.rows)));
        }
        pub fn span(s: struct { cols: i32, scale: f32 }) i32 {
            return @intFromFloat(@as(f32, @floatFromInt(s.cols)) * s.scale);
        }
        pub fn rise(s: struct { rows: i32, scale: f32 }) i32 {
            return @intFromFloat(@as(f32, @floatFromInt(s.rows)) * s.scale);
        }
        pub fn ox(s: struct { span: i32 }) i32 {
            return pad + @divTrunc(vp - s.span, 2);
        }
        pub fn oy(s: struct { rise: i32 }) i32 {
            return pad + @divTrunc(vp - s.rise, 2);
        }
        pub fn cur(s: struct { size: i32, scale: f32 }) f32 {
            return @as(f32, @floatFromInt(s.size)) * s.scale;
        }
    };
});

// ─── Drawing Helpers ─────────────────────────────────────────────────────────

fn toFC(col: sdl3.pixels.Color) sdl3.pixels.FColor {
    return .{
        .r = @as(f32, @floatFromInt(col.r)) / 255.0,
        .g = @as(f32, @floatFromInt(col.g)) / 255.0,
        .b = @as(f32, @floatFromInt(col.b)) / 255.0,
        .a = @as(f32, @floatFromInt(col.a)) / 255.0,
    };
}

fn dc(ren: sdl3.render.Renderer, col: sdl3.pixels.Color) void {
    ren.setDrawColor(col) catch {};
}

fn fillCircle(ren: sdl3.render.Renderer, cx: f32, cy: f32, radius: f32, col: sdl3.pixels.Color) void {
    dc(ren, col);
    const r: i32 = @intFromFloat(@max(radius, 0.5));
    var dy: i32 = -r;
    while (dy <= r) : (dy += 1) {
        const dyf: f32 = @floatFromInt(dy);
        const dx: f32 = @sqrt(@max(radius * radius - dyf * dyf, 0));
        ren.renderFillRect(.{ .x = cx - dx, .y = cy + dyf, .w = dx * 2.0, .h = 1.0 }) catch {};
    }
}

fn thickLine(ren: sdl3.render.Renderer, x1: f32, y1: f32, x2: f32, y2: f32, thickness: f32, col: sdl3.pixels.Color) void {
    const ddx = x2 - x1;
    const ddy = y2 - y1;
    const len = @sqrt(ddx * ddx + ddy * ddy);
    if (len < 0.001) return;
    const half = thickness / 2.0;
    const nx = -ddy / len * half;
    const ny = ddx / len * half;
    const fc = toFC(col);
    const z = sdl3.rect.FPoint{ .x = 0, .y = 0 };
    const verts = [_]sdl3.render.Vertex{
        .{ .position = .{ .x = x1 + nx, .y = y1 + ny }, .color = fc, .tex_coord = z },
        .{ .position = .{ .x = x1 - nx, .y = y1 - ny }, .color = fc, .tex_coord = z },
        .{ .position = .{ .x = x2 - nx, .y = y2 - ny }, .color = fc, .tex_coord = z },
        .{ .position = .{ .x = x2 + nx, .y = y2 + ny }, .color = fc, .tex_coord = z },
    };
    const idx = [_]c_int{ 0, 1, 2, 0, 2, 3 };
    ren.renderGeometry(null, &verts, &idx) catch {};
}

fn circleOutline(ren: sdl3.render.Renderer, cx: f32, cy: f32, radius: f32, col: sdl3.pixels.Color) void {
    dc(ren, col);
    const segs: usize = 72;
    var pts: [segs + 1]sdl3.rect.FPoint = undefined;
    for (0..segs + 1) |i| {
        const a = @as(f32, @floatFromInt(i)) * std.math.tau / @as(f32, @floatFromInt(segs));
        pts[i] = .{ .x = cx + @cos(a) * radius, .y = cy + @sin(a) * radius };
    }
    ren.renderLines(&pts) catch {};
}

fn txt(ren: sdl3.render.Renderer, x: i32, y: i32, col: sdl3.pixels.Color, s: [:0]const u8) void {
    dc(ren, col);
    ren.renderDebugText(.{ .x = @floatFromInt(x), .y = @floatFromInt(y) }, s) catch {};
}

// ─── Per-Frame Input ─────────────────────────────────────────────────────────

const FrameInput = struct {
    tab: bool = false,
    e_key: bool = false,
    lbracket: bool = false,
    rbracket: bool = false,
    z_key: bool = false,
    s_key: bool = false,
    c_key: bool = false,
    wheel: f32 = 0,

    fn reset(self: *FrameInput) void { self.* = .{}; }
};

// ─── Application State ───────────────────────────────────────────────────────

const App = struct {
    ui: Ui = .{},
    ren: sdl3.render.Renderer,

    canvas: ?sdl3.render.Texture = null,

    snaps: [snap_cap]?sdl3.surface.Surface = [_]?sdl3.surface.Surface{null} ** snap_cap,
    sn: usize = 0,

    sr_x: [ring_cap]f32 = undefined,
    sr_y: [ring_cap]f32 = undefined,
    sr_i: usize = 0,

    inking: bool = false,
    last_x: f32 = 0,
    last_y: f32 = 0,

    do_clear: bool = false,
    do_save:  bool = false,
    note: [:0]const u8 = "",
    note_t: i32 = 0,
    buf: [128]u8 = undefined,
    frame: FrameInput = .{},

    pub fn init(ren: sdl3.render.Renderer) App {
        var self = App{ .ren = ren };
        self.ui.dirty = Ui.Mask.initFull();
        _ = self.ui.flush();
        return self;
    }

    pub fn deinit(self: *App) void {
        if (self.canvas) |t| t.deinit();
        for (&self.snaps) |*s| if (s.*) |surf| surf.deinit();
    }

    fn pushUndo(self: *App) void {
        const canvas = self.canvas orelse return;
        self.ren.setTarget(canvas) catch return;
        const img = self.ren.readPixels(null) catch { self.ren.setTarget(null) catch {}; return; };
        self.ren.setTarget(null) catch {};
        if (self.sn < snap_cap) {
            self.snaps[self.sn] = img;
            self.sn += 1;
            return;
        }
        if (self.snaps[0]) |old| old.deinit();
        for (0..snap_cap - 1) |i| self.snaps[i] = self.snaps[i + 1];
        self.snaps[snap_cap - 1] = img;
    }

    pub fn onKeyDown(self: *App, k: sdl3.events.Keyboard) void {
        if (k.repeat) return;
        const sc = k.scancode orelse return;
        switch (sc) {
            .tab          => self.frame.tab = true,
            .e            => self.frame.e_key = true,
            .left_bracket => self.frame.lbracket = true,
            .right_bracket=> self.frame.rbracket = true,
            .z            => self.frame.z_key = true,
            .s            => self.frame.s_key = true,
            .c            => self.frame.c_key = true,
            else => {},
        }
    }

    pub fn onWheel(self: *App, w: sdl3.events.MouseWheel) void {
        self.frame.wheel += w.scroll_y;
    }

    pub fn handleInput(self: *App) void {
        const keys = sdl3.keyboard.getState();
        const ctrl = keys[@intFromEnum(sdl3.Scancode.left_ctrl)] or
                     keys[@intFromEnum(sdl3.Scancode.right_ctrl)];

        if (self.frame.tab or self.frame.e_key)
            self.ui.set(.tool, 1 - self.ui.get(.tool));
        if (self.frame.lbracket)
            self.ui.set(.page, @max(0, self.ui.get(.page) - 1));
        if (self.frame.rbracket)
            self.ui.set(.page, @min(n_pg - 1, self.ui.get(.page) + 1));

        if (self.frame.wheel != 0) {
            const w: i32 = @intFromFloat(self.frame.wheel);
            if (ctrl)
                self.ui.set(.stab, std.math.clamp(self.ui.get(.stab) + w, 1, @as(i32, ring_cap)))
            else
                self.ui.set(.size, std.math.clamp(self.ui.get(.size) + w, 1, 120));
        }

        if (ctrl and self.frame.z_key and self.canvas != null and self.sn > 0) {
            self.sn -= 1;
            if (self.snaps[self.sn]) |snap| {
                const canvas = self.canvas.?;
                const tmp = self.ren.createTextureFromSurface(snap) catch { snap.deinit(); self.snaps[self.sn] = null; return; };
                defer tmp.deinit();
                tmp.setBlendMode(.none) catch {};
                self.ren.setTarget(canvas) catch {};
                self.ren.renderTexture(tmp, null, null) catch {};
                self.ren.setTarget(null) catch {};
                snap.deinit();
                self.snaps[self.sn] = null;
                self.inking = false;
            }
        }
        if (ctrl and self.frame.s_key)  self.do_save  = true;
        if (!ctrl and self.frame.c_key) self.do_clear = true;
    }

    pub fn updateCanvas(self: *App, flags: Ui.Mask) void {
        const resized = comptime Ui.watch(&.{ .cols, .rows });
        var overlap = flags;
        overlap.setIntersection(resized);

        if (self.canvas == null or overlap.count() > 0) {
            for (&self.snaps) |*s| { if (s.*) |surf| surf.deinit(); s.* = null; }
            self.sn = 0;
            if (self.canvas) |t| t.deinit();
            self.canvas = self.ren.createTexture(
                sdl3.pixels.Format.array_rgba_32, .target,
                @intCast(self.ui.get(.cols)), @intCast(self.ui.get(.rows)),
            ) catch null;
            if (self.canvas) |t| {
                t.setScaleMode(.nearest) catch {};
                self.ren.setTarget(t) catch {};
                dc(self.ren, paper);
                self.ren.clear() catch {};
                self.ren.setTarget(null) catch {};
            }
            self.inking = false; self.do_clear = false;
        }
        if (self.do_clear) if (self.canvas) |canvas| {
            self.pushUndo();
            self.ren.setTarget(canvas) catch {};
            dc(self.ren, paper);
            self.ren.clear() catch {};
            self.ren.setTarget(null) catch {};
            self.inking = false; self.do_clear = false;
        };
        if (self.do_save) if (self.canvas) |canvas| {
            self.ren.setTarget(canvas) catch { self.do_save = false; return; };
            const img = self.ren.readPixels(null) catch { self.ren.setTarget(null) catch {}; self.do_save = false; return; };
            self.ren.setTarget(null) catch {};
            defer img.deinit();
            sdl3.image.savePng(img, "sumi.png") catch {};
            self.note = "exported  sumi.png"; self.note_t = 180;
            self.do_save = false;
        };
    }

    pub fn processStroke(self: *App) void {
        const canvas = self.canvas orelse return;
        const btns, const mx_raw, const my_raw = sdl3.mouse.getState();
        const z   = self.ui.get(.scale);
        const ofx : f32 = @floatFromInt(self.ui.get(.ox));
        const ofy : f32 = @floatFromInt(self.ui.get(.oy));
        const mx  = (mx_raw - ofx) / z;
        const my  = (my_raw - ofy) / z;
        const cw  : f32 = @floatFromInt(self.ui.get(.cols));
        const ch  : f32 = @floatFromInt(self.ui.get(.rows));
        const hit = mx >= 0 and mx < cw and my >= 0 and my < ch;

        const lmb     = btns.left;
        const rmb     = btns.right;
        const press   = (lmb or rmb) and hit;
        const erasing = rmb or (lmb and self.ui.get(.tool) == 1);
        const color   = if (erasing) paper else ink;
        const rad     : f32 = @floatFromInt(self.ui.get(.size));

        if (press) {
            if (!self.inking) {
                self.pushUndo();
                for (&self.sr_x) |*v| v.* = mx;
                for (&self.sr_y) |*v| v.* = my;
                self.sr_i = 0;

                self.ren.setTarget(canvas) catch return;
                fillCircle(self.ren, mx, my, rad, color);
                self.ren.setTarget(null) catch {};
                self.last_x = mx; self.last_y = my; self.inking = true;
            } else {
                self.sr_x[self.sr_i] = mx; self.sr_y[self.sr_i] = my;
                self.sr_i = (self.sr_i + 1) % ring_cap;

                const n  : usize = @intCast(self.ui.get(.stab));
                const nf : f32   = @floatFromInt(n);
                var sx : f32 = 0;
                var sy : f32 = 0;
                for (0..n) |i| {
                    const k = (self.sr_i + ring_cap - 1 - i) % ring_cap;
                    sx += self.sr_x[k]; sy += self.sr_y[k];
                }
                const qx = sx / nf;
                const qy = sy / nf;

                if (qx != self.last_x or qy != self.last_y) {
                    self.ren.setTarget(canvas) catch return;
                    thickLine(self.ren, self.last_x, self.last_y, qx, qy, rad * 2, color);
                    fillCircle(self.ren, self.last_x, self.last_y, rad, color);
                    fillCircle(self.ren, qx, qy, rad, color);
                    self.ren.setTarget(null) catch {};
                    self.last_x = qx; self.last_y = qy;
                }
            }
        } else if (!lmb and !rmb) {
            self.inking = false;
        }
    }

    pub fn render(self: *App) void {
        const ren = self.ren;
        dc(ren, c_bg);
        ren.clear() catch {};

        const btns, const mx_raw, const my_raw = sdl3.mouse.getState();
        const z   = self.ui.get(.scale);
        const ofx : f32 = @floatFromInt(self.ui.get(.ox));
        const ofy : f32 = @floatFromInt(self.ui.get(.oy));
        const cw  : f32 = @floatFromInt(self.ui.get(.cols));
        const ch  : f32 = @floatFromInt(self.ui.get(.rows));
        const mx  = (mx_raw - ofx) / z;
        const my  = (my_raw - ofy) / z;
        const hit = mx >= 0 and mx < cw and my >= 0 and my < ch;
        const erasing = btns.right or (btns.left and self.ui.get(.tool) == 1);

        // canvas well
        dc(ren, c_well);
        ren.renderFillRect(.{ .x = @floatFromInt(pad - 2), .y = @floatFromInt(pad - 2),
                              .w = @floatFromInt(vp + 4),   .h = @floatFromInt(vp + 4) }) catch {};

        // canvas texture
        if (self.canvas) |canvas|
            ren.renderTexture(canvas,
                .{ .x = 0, .y = 0, .w = cw, .h = ch },
                .{ .x = ofx, .y = ofy,
                   .w = @floatFromInt(self.ui.get(.span)),
                   .h = @floatFromInt(self.ui.get(.rise)) },
            ) catch {};

        // canvas border
        dc(ren, c_line);
        ren.renderRect(.{
            .x = @as(f32, @floatFromInt(self.ui.get(.ox) - 1)),
            .y = @as(f32, @floatFromInt(self.ui.get(.oy) - 1)),
            .w = @as(f32, @floatFromInt(self.ui.get(.span) + 2)),
            .h = @as(f32, @floatFromInt(self.ui.get(.rise) + 2)),
        }) catch {};

        // cursor
        if (hit) {
            sdl3.mouse.hide() catch {};
            const cr = @max(self.ui.get(.cur), 1.5);
            const cx = ofx + mx * z;
            const cy = ofy + my * z;
            const cc: sdl3.pixels.Color = if (erasing)
                .{ .r = 80, .g = 140, .b = 220, .a = 180 }
            else if (self.ui.get(.tool) == 1)
                .{ .r = 80, .g = 140, .b = 220, .a = 120 }
            else
                .{ .r = 180, .g = 180, .b = 180, .a = 170 };
            circleOutline(ren, cx, cy, cr, cc);
            dc(ren, .{ .r = 200, .g = 200, .b = 200, .a = 100 });
            ren.renderPoint(.{ .x = cx, .y = cy }) catch {};
        } else sdl3.mouse.show() catch {};

        // divider
        dc(ren, c_line);
        ren.renderLine(
            .{ .x = @floatFromInt(side - 1), .y = @floatFromInt(pad) },
            .{ .x = @floatFromInt(side - 1), .y = @floatFromInt(win_h - pad) },
        ) catch {};

        // ─── sidebar ─────────────────────────────────────────────────
        const px = side + 10;
        var py : i32 = pad + 4;

        txt(ren, px, py, c_hi, "SUMI"); py += 16;
        dc(ren, c_line);
        ren.renderLine(
            .{ .x = @floatFromInt(px), .y = @floatFromInt(py) },
            .{ .x = @floatFromInt(win_w - pad), .y = @floatFromInt(py) },
        ) catch {};
        py += 10;

        txt(ren, px, py, c_mute, "TOOL"); py += 12;
        {
            const t = self.ui.get(.tool);
            txt(ren, px, py, if (t == 0) c_hi else c_dim, "PEN");
            txt(ren, px + 40, py, if (t == 1) c_hi else c_dim, "ERASER");
        }
        py += 18;

        txt(ren, px, py, c_mute, "SIZE"); py += 12;
        dc(ren, c_hi);
        ren.renderDebugTextFormat(
            .{ .x = @floatFromInt(px), .y = @floatFromInt(py) },
            "{d} px", .{self.ui.get(.size)},
        ) catch {};
        py += 16;

        {
            const bx: f32 = @floatFromInt(px + 36);
            const by: f32 = @floatFromInt(py + 36);
            circleOutline(ren, bx, by, 32, c_line);
            const vr = @min(@as(f32, @floatFromInt(self.ui.get(.size))) * 0.32, 32.0);
            if (vr >= 0.5)
                fillCircle(ren, bx, by, vr, if (self.ui.get(.tool) == 0) ink else c_dim);
        }
        py += 82;

        txt(ren, px, py, c_mute, "STABILIZER"); py += 12;
        dc(ren, c_hi);
        ren.renderDebugTextFormat(
            .{ .x = @floatFromInt(px), .y = @floatFromInt(py) },
            "{d}", .{self.ui.get(.stab)},
        ) catch {};
        {
            const bw : i32 = 110;
            const fw = @divTrunc(bw * self.ui.get(.stab), @as(i32, ring_cap));
            dc(ren, c_line);
            ren.renderFillRect(.{ .x = @floatFromInt(px + 24), .y = @floatFromInt(py + 2), .w = @floatFromInt(bw), .h = 2 }) catch {};
            dc(ren, c_hi);
            ren.renderFillRect(.{ .x = @floatFromInt(px + 24), .y = @floatFromInt(py + 1), .w = @floatFromInt(fw), .h = 4 }) catch {};
        }
        py += 20;

        txt(ren, px, py, c_mute, "PAGE"); py += 12;
        dc(ren, c_hi);
        ren.renderDebugTextFormat(
            .{ .x = @floatFromInt(px), .y = @floatFromInt(py) },
            "{d} x {d}", .{ self.ui.get(.cols), self.ui.get(.rows) },
        ) catch {};
        py += 14;

        for (pg_tag, 0..) |tag, i| {
            const on = self.ui.get(.page) == @as(i32, @intCast(i));
            txt(ren, px + @as(i32, @intCast(i)) * 28, py, if (on) c_hi else c_dim, tag);
        }
        py += 16;

        dc(ren, c_mute);
        ren.renderDebugTextFormat(
            .{ .x = @floatFromInt(px), .y = @floatFromInt(py) },
            "undo {d}/{d}", .{ self.sn, snap_cap },
        ) catch {};
        py += 16;

        dc(ren, c_line);
        ren.renderLine(
            .{ .x = @floatFromInt(px), .y = @floatFromInt(py) },
            .{ .x = @floatFromInt(win_w - pad), .y = @floatFromInt(py) },
        ) catch {};
        py += 8;
        txt(ren, px, py, c_mute, "KEYS"); py += 12;
        for ([_][:0]const u8{
            "scroll     brush size",
            "ctrl+scrl  stabilizer",
            "tab / E    tool",
            "[    ]     page size",
            "ctrl+Z     undo",
            "ctrl+S     export png",
            "C          clear",
        }) |line| {
            txt(ren, px, py, c_dim, line);
            py += 10;
        }

        if (self.note_t > 0) {
            self.note_t -= 1;
            const a : u8 = if (self.note_t > 30) 220
                else @intCast(@min(self.note_t * 7, @as(i32, 220)));
            dc(ren, .{ .r = 170, .g = 200, .b = 255, .a = a });
            ren.renderDebugText(
                .{ .x = @floatFromInt(pad + 4), .y = @floatFromInt(win_h - pad - 12) },
                self.note,
            ) catch {};
        }
    }
};

// ─── Entry ───────────────────────────────────────────────────────────────────

pub fn main() !void {
    defer sdl3.shutdown();
    try sdl3.init(.{ .video = true });
    defer sdl3.quit(.{ .video = true });

    const window = try sdl3.video.Window.init("Sumi", @intCast(win_w), @intCast(win_h), .{});
    defer window.deinit();

    const ren = try sdl3.render.Renderer.init(window, null);
    defer ren.deinit();
    ren.setVSync(.{ .on_each_num_refresh = 1 }) catch {};

    var app = App.init(ren);
    defer app.deinit();

    var running = true;
    while (running) {
        app.frame.reset();
        while (sdl3.events.poll()) |ev| {
            switch (ev) {
                .quit => running = false,
                .key_down => |k| app.onKeyDown(k),
                .mouse_wheel => |w| app.onWheel(w),
                else => {},
            }
        }
        app.handleInput();
        const flags = app.ui.flush();
        app.updateCanvas(flags);
        app.processStroke();
        app.render();
        ren.present() catch {};
    }
}
