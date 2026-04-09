const std  = @import("std");
const sdl3 = @import("sdl3");
const react = @import("react");

// ── Layout ────────────────────────────────────────────────────────────────────

const vp    : i32 = 600;
const pad   : i32 = 16;
const side  : i32 = pad + vp + pad;
const win_w : i32 = side + 200 + pad;
const win_h : i32 = pad + vp + pad;

// ── Palette ───────────────────────────────────────────────────────────────────

const C = sdl3.pixels.Color;
const c_ink  : C = .{ .r=0,   .g=0,   .b=0,   .a=255 };
const c_paper: C = .{ .r=255, .g=255, .b=255, .a=255 };
const c_bg   : C = .{ .r=18,  .g=18,  .b=22,  .a=255 };
const c_well : C = .{ .r=30,  .g=30,  .b=36,  .a=255 };
const c_line : C = .{ .r=46,  .g=46,  .b=54,  .a=255 };
const c_dim  : C = .{ .r=82,  .g=82,  .b=96,  .a=255 };
const c_mute : C = .{ .r=56,  .g=56,  .b=66,  .a=255 };
const c_hi   : C = .{ .r=255, .g=255, .b=255, .a=255 };

// ── Pages ─────────────────────────────────────────────────────────────────────

const Page      = struct { w: i32, h: i32 };
const pages     = [_]Page{
    .{.w=210,.h=294}, .{.w=420,.h=588}, .{.w=630,.h=882},
    .{.w=1050,.h=1470}, .{.w=1470,.h=2058},
};
const page_tags = [_][:0]const u8{ "XS","S","M","L","XL" };

// ── Tuning ────────────────────────────────────────────────────────────────────

const undo_cap : usize = 20;
const ring_cap : usize = 16;

// ── Reactive State ────────────────────────────────────────────────────────────

const Ui = react.Signals(struct {

    page: i32 = 2,
    size: i32 = 3,
    tool: i32 = 0,
    stab: i32 = 6,

    pub fn cols (s: struct { page: i32 }) i32 {
        return pages[@intCast(s.page)].w;
    }

    pub fn rows (s: struct { page: i32 }) i32 {
        return pages[@intCast(s.page)].h;
    }

    pub fn scale(s: struct { cols: i32, rows: i32 }) f32 {
        return @as(f32, @floatFromInt(vp)) / @as(f32, @floatFromInt(@max(s.cols, s.rows)));
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
});

// ── Draw Primitives ───────────────────────────────────────────────────────────

const R = sdl3.render.Renderer;

fn setCol(r: R, c: C) void { r.setDrawColor(c) catch {}; }

fn disc(r: R, cx: f32, cy: f32, rad: f32, c: C) void {
    setCol(r, c);
    const ri: i32 = @intFromFloat(@max(rad, 0.5));
    var dy: i32 = -ri;
    while (dy <= ri) : (dy += 1) {
        const f: f32 = @floatFromInt(dy);
        const dx = @sqrt(@max(rad * rad - f * f, 0));
        r.renderFillRect(.{ .x=cx-dx, .y=cy+f, .w=dx*2, .h=1 }) catch {};
    }
}

fn fatLine(r: R, x0: f32, y0: f32, x1: f32, y1: f32, w: f32, c: C) void {
    const dx = x1-x0; const dy = y1-y0; const len = @sqrt(dx*dx + dy*dy);
    if (len < 0.001) return;
    const h = w / 2; const nx = -dy/len*h; const ny = dx/len*h;
    const fc = sdl3.pixels.FColor{
        .r=@as(f32,@floatFromInt(c.r))/255, .g=@as(f32,@floatFromInt(c.g))/255,
        .b=@as(f32,@floatFromInt(c.b))/255, .a=@as(f32,@floatFromInt(c.a))/255 };
    const z = sdl3.rect.FPoint{ .x=0, .y=0 };
    r.renderGeometry(null, &[4]sdl3.render.Vertex{
        .{ .position=.{.x=x0+nx,.y=y0+ny}, .color=fc, .tex_coord=z },
        .{ .position=.{.x=x0-nx,.y=y0-ny}, .color=fc, .tex_coord=z },
        .{ .position=.{.x=x1-nx,.y=y1-ny}, .color=fc, .tex_coord=z },
        .{ .position=.{.x=x1+nx,.y=y1+ny}, .color=fc, .tex_coord=z },
    }, &[_]c_int{0,1,2,0,2,3}) catch {};
}

fn circleOutline(r: R, cx: f32, cy: f32, rad: f32, c: C) void {
    setCol(r, c);
    const N = 72; var pts: [N+1]sdl3.rect.FPoint = undefined;
    for (0..N+1) |i| {
        const a = @as(f32,@floatFromInt(i)) * std.math.tau / N;
        pts[i] = .{ .x=cx+@cos(a)*rad, .y=cy+@sin(a)*rad };
    }
    r.renderLines(&pts) catch {};
}

fn label(r: R, x: i32, y: i32, c: C, s: [:0]const u8) void {
    setCol(r, c);
    r.renderDebugText(.{ .x=@floatFromInt(x), .y=@floatFromInt(y) }, s) catch {};
}

// ── App ───────────────────────────────────────────────────────────────────────

const App = struct {
    ui:     Ui = .{},
    ren:    R,
    canvas: ?sdl3.render.Texture = null,

    snaps:  [undo_cap]?sdl3.surface.Surface = .{null} ** undo_cap,
    snap_n: usize = 0,

    rx: [ring_cap]f32 = undefined,
    ry: [ring_cap]f32 = undefined,
    ri: usize = 0,

    inking: bool = false,
    pen_x:  f32  = 0,
    pen_y:  f32  = 0,

    note:   [:0]const u8 = "",
    note_t: i32 = 0,

    fn init(ren: R) App {
        var a = App{ .ren = ren };
        a.ui.dirty = Ui.Mask.initFull();
        _ = a.ui.flush();
        return a;
    }

    fn deinit(a: *App) void {
        if (a.canvas) |t| t.deinit();
        for (&a.snaps) |*s| if (s.*) |sf| { sf.deinit(); s.* = null; };
    }

    // ── Canvas ────────────────────────────────────────────────────────────────

    fn resizeCanvas(a: *App) void {
        for (&a.snaps) |*s| { if (s.*) |sf| sf.deinit(); s.* = null; }
        a.snap_n = 0; a.inking = false;
        if (a.canvas) |t| t.deinit();
        a.canvas = a.ren.createTexture(sdl3.pixels.Format.array_rgba_32, .target,
            @intCast(a.ui.get(.cols)), @intCast(a.ui.get(.rows))) catch null;
        if (a.canvas) |t| {
            t.setScaleMode(.nearest) catch {};
            a.ren.setTarget(t) catch return;
            setCol(a.ren, c_paper); a.ren.clear() catch {};
            a.ren.setTarget(null) catch {};
        }
    }

    fn clearCanvas(a: *App) void {
        a.pushUndo(); a.inking = false;
        a.ren.setTarget(a.canvas orelse return) catch return;
        setCol(a.ren, c_paper); a.ren.clear() catch {};
        a.ren.setTarget(null) catch {};
    }

    fn exportCanvas(a: *App) void {
        a.ren.setTarget(a.canvas orelse return) catch return;
        const snap = a.ren.readPixels(null) catch { a.ren.setTarget(null) catch {}; return; };
        a.ren.setTarget(null) catch {};
        defer snap.deinit();
        sdl3.image.savePng(snap, "sumi.png") catch {};
        a.note = "exported  sumi.png"; a.note_t = 180;
    }

    // ── Undo ──────────────────────────────────────────────────────────────────

    fn pushUndo(a: *App) void {
        a.ren.setTarget(a.canvas orelse return) catch return;
        const snap = a.ren.readPixels(null) catch { a.ren.setTarget(null) catch {}; return; };
        a.ren.setTarget(null) catch {};
        if (a.snap_n < undo_cap) {
            a.snaps[a.snap_n] = snap; a.snap_n += 1;
        } else {
            if (a.snaps[0]) |s| s.deinit();
            std.mem.copyForwards(?sdl3.surface.Surface, a.snaps[0..undo_cap-1], a.snaps[1..undo_cap]);
            a.snaps[undo_cap-1] = snap;
        }
    }

    fn popUndo(a: *App) void {
        if (a.snap_n == 0) return;
        a.snap_n -= 1;
        const snap = a.snaps[a.snap_n] orelse return;
        a.snaps[a.snap_n] = null; defer snap.deinit();
        const t = a.canvas orelse return;
        const tmp = a.ren.createTextureFromSurface(snap) catch return;
        defer tmp.deinit();
        tmp.setBlendMode(.none) catch {};
        a.ren.setTarget(t) catch return;
        a.ren.renderTexture(tmp, null, null) catch {};
        a.ren.setTarget(null) catch {};
        a.inking = false;
    }

    // ── Stroke ────────────────────────────────────────────────────────────────

    fn stroke(a: *App) void {
        const btns, const mx_raw, const my_raw = sdl3.mouse.getState();
        if (!btns.left and !btns.right) { a.inking = false; return; }

        const z   = a.ui.get(.scale);
        const ofx : f32 = @floatFromInt(a.ui.get(.ox));
        const ofy : f32 = @floatFromInt(a.ui.get(.oy));
        const mx  = (mx_raw - ofx) / z;
        const my  = (my_raw - ofy) / z;
        const cw  : f32 = @floatFromInt(a.ui.get(.cols));
        const ch  : f32 = @floatFromInt(a.ui.get(.rows));
        if (mx < 0 or mx >= cw or my < 0 or my >= ch) return;

        const erase = btns.right or (btns.left and a.ui.get(.tool) == 1);
        const paint = if (erase) c_paper else c_ink;
        const rad  : f32 = @floatFromInt(a.ui.get(.size));

        a.ren.setTarget(a.canvas orelse return) catch return;
        defer a.ren.setTarget(null) catch {};

        if (!a.inking) {
            a.pushUndo();
            for (&a.rx) |*v| v.* = mx;
            for (&a.ry) |*v| v.* = my;
            a.ri = 0; a.inking = true;
            disc(a.ren, mx, my, rad, paint);
            a.pen_x = mx; a.pen_y = my;
            return;
        }

        a.rx[a.ri] = mx; a.ry[a.ri] = my;
        a.ri = (a.ri + 1) % ring_cap;

        const n  : usize = @intCast(a.ui.get(.stab));
        const nf : f32   = @floatFromInt(n);
        var sx: f32 = 0; var sy: f32 = 0;
        for (0..n) |i| {
            const k = (a.ri + ring_cap - 1 - i) % ring_cap;
            sx += a.rx[k]; sy += a.ry[k];
        }
        const qx = sx / nf; const qy = sy / nf;
        if (qx == a.pen_x and qy == a.pen_y) return;

        fatLine(a.ren, a.pen_x, a.pen_y, qx, qy, rad*2, paint);
        disc(a.ren, a.pen_x, a.pen_y, rad, paint);
        disc(a.ren, qx, qy, rad, paint);
        a.pen_x = qx; a.pen_y = qy;
    }

    // ── Render ────────────────────────────────────────────────────────────────

    fn draw(a: *App) void {
        const r = a.ren;
        setCol(r, c_bg); r.clear() catch {};

        // canvas well
        setCol(r, c_well);
        r.renderFillRect(.{ .x=@floatFromInt(pad-2), .y=@floatFromInt(pad-2),
                            .w=@floatFromInt(vp+4),   .h=@floatFromInt(vp+4) }) catch {};

        // canvas texture
        if (a.canvas) |t|
            r.renderTexture(t,
                .{ .x=0, .y=0, .w=@floatFromInt(a.ui.get(.cols)), .h=@floatFromInt(a.ui.get(.rows)) },
                .{ .x=@floatFromInt(a.ui.get(.ox)),   .y=@floatFromInt(a.ui.get(.oy)),
                   .w=@floatFromInt(a.ui.get(.span)), .h=@floatFromInt(a.ui.get(.rise)) },
            ) catch {};

        // canvas border
        setCol(r, c_line);
        r.renderRect(.{
            .x=@as(f32,@floatFromInt(a.ui.get(.ox)-1)),  .y=@as(f32,@floatFromInt(a.ui.get(.oy)-1)),
            .w=@as(f32,@floatFromInt(a.ui.get(.span)+2)),.h=@as(f32,@floatFromInt(a.ui.get(.rise)+2)),
        }) catch {};

        // cursor
        {
            const btns, const mx_raw, const my_raw = sdl3.mouse.getState();
            const z   = a.ui.get(.scale);
            const ofx : f32 = @floatFromInt(a.ui.get(.ox));
            const ofy : f32 = @floatFromInt(a.ui.get(.oy));
            const mx  = (mx_raw - ofx) / z;
            const my  = (my_raw - ofy) / z;
            const cw  : f32 = @floatFromInt(a.ui.get(.cols));
            const ch  : f32 = @floatFromInt(a.ui.get(.rows));
            if (mx >= 0 and mx < cw and my >= 0 and my < ch) {
                sdl3.mouse.hide() catch {};
                const erase = btns.right or (btns.left and a.ui.get(.tool) == 1);
                const cc: C = if (erase)                  .{ .r=80,.g=140,.b=220,.a=180 }
                              else if (a.ui.get(.tool)==1) .{ .r=80,.g=140,.b=220,.a=120 }
                              else                         .{ .r=180,.g=180,.b=180,.a=170 };
                circleOutline(r, ofx + mx*z, ofy + my*z, @max(a.ui.get(.cur), 1.5), cc);
                setCol(r, .{ .r=200, .g=200, .b=200, .a=100 });
                r.renderPoint(.{ .x=ofx+mx*z, .y=ofy+my*z }) catch {};
            } else sdl3.mouse.show() catch {};
        }

        // panel divider
        setCol(r, c_line);
        r.renderLine(.{ .x=@floatFromInt(side-1), .y=@floatFromInt(pad) },
                      .{ .x=@floatFromInt(side-1), .y=@floatFromInt(win_h-pad) }) catch {};

        // ── sidebar ───────────────────────────────────────────────────────────
        const px = side + 10; var py: i32 = pad + 4;

        label(r, px, py, c_hi, "SUMI"); py += 16;
        setCol(r, c_line);
        r.renderLine(.{.x=@floatFromInt(px),.y=@floatFromInt(py)},
                      .{.x=@floatFromInt(win_w-pad),.y=@floatFromInt(py)}) catch {};
        py += 10;

        label(r, px,    py, c_mute, "TOOL"); py += 12;
        label(r, px,    py, if (a.ui.get(.tool)==0) c_hi else c_dim, "PEN");
        label(r, px+40, py, if (a.ui.get(.tool)==1) c_hi else c_dim, "ERASER");
        py += 18;

        label(r, px, py, c_mute, "SIZE"); py += 12;
        r.renderDebugTextFormat(.{.x=@floatFromInt(px),.y=@floatFromInt(py)},
            "{d} px", .{a.ui.get(.size)}) catch {};
        py += 16;
        {   // brush preview
            const bx: f32 = @floatFromInt(px + 36);
            const by: f32 = @floatFromInt(py + 36);
            circleOutline(r, bx, by, 32, c_line);
            const vr = @min(@as(f32, @floatFromInt(a.ui.get(.size))) * 0.32, 32.0);
            if (vr >= 0.5) disc(r, bx, by, vr, if (a.ui.get(.tool)==0) c_ink else c_dim);
        }
        py += 82;

        label(r, px, py, c_mute, "STABILIZER"); py += 12;
        r.renderDebugTextFormat(.{.x=@floatFromInt(px),.y=@floatFromInt(py)},
            "{d}", .{a.ui.get(.stab)}) catch {};
        {   // stabilizer bar
            const bw: i32 = 110;
            const fw = @divTrunc(bw * a.ui.get(.stab), @as(i32, ring_cap));
            setCol(r, c_line); r.renderFillRect(.{.x=@floatFromInt(px+24),.y=@floatFromInt(py+2),.w=@floatFromInt(bw),.h=2}) catch {};
            setCol(r, c_hi);   r.renderFillRect(.{.x=@floatFromInt(px+24),.y=@floatFromInt(py+1),.w=@floatFromInt(fw),.h=4}) catch {};
        }
        py += 20;

        label(r, px, py, c_mute, "PAGE"); py += 12;
        r.renderDebugTextFormat(.{.x=@floatFromInt(px),.y=@floatFromInt(py)},
            "{d} x {d}", .{ a.ui.get(.cols), a.ui.get(.rows) }) catch {};
        py += 14;
        for (page_tags, 0..) |tag, i|
            label(r, px + @as(i32,@intCast(i))*28, py,
                if (a.ui.get(.page)==@as(i32,@intCast(i))) c_hi else c_dim, tag);
        py += 16;

        setCol(r, c_mute);
        r.renderDebugTextFormat(.{.x=@floatFromInt(px),.y=@floatFromInt(py)},
            "undo {d}/{d}", .{ a.snap_n, undo_cap }) catch {};
        py += 16;

        setCol(r, c_line);
        r.renderLine(.{.x=@floatFromInt(px),.y=@floatFromInt(py)},
                      .{.x=@floatFromInt(win_w-pad),.y=@floatFromInt(py)}) catch {};
        py += 8;
        label(r, px, py, c_mute, "KEYS"); py += 12;
        for ([_][:0]const u8{
            "scroll     brush size",
            "ctrl+scrl  stabilizer",
            "tab / E    tool",
            "[    ]     page size",
            "ctrl+Z     undo",
            "ctrl+S     export png",
            "C          clear",
        }) |ln| { label(r, px, py, c_dim, ln); py += 10; }

        // notification
        if (a.note_t > 0) {
            const alpha: u8 = if (a.note_t > 30) 220 else @intCast(@min(a.note_t * 7, 220));
            a.note_t -= 1;
            setCol(r, .{ .r=170, .g=200, .b=255, .a=alpha });
            r.renderDebugText(.{.x=@floatFromInt(pad+4),.y=@floatFromInt(win_h-pad-12)}, a.note) catch {};
        }
    }
};

// ── Entry ─────────────────────────────────────────────────────────────────────

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
    app.resizeCanvas();

    var running = true;
    while (running) {

        // ── Input ─────────────────────────────────────────────────────────────
        var wheel: f32 = 0;
        var tab=false; var e_key=false; var lbr=false; var rbr=false;
        var z_key=false; var s_key=false; var c_key=false;

        while (sdl3.events.poll()) |ev| switch (ev) {
            .quit     => running = false,
            .key_down => |k| if (!k.repeat) switch (k.scancode orelse continue) {
                .tab           => tab   = true,
                .e             => e_key = true,
                .left_bracket  => lbr   = true,
                .right_bracket => rbr   = true,
                .z             => z_key = true,
                .s             => s_key = true,
                .c             => c_key = true,
                else => {},
            },
            .mouse_wheel => |w| wheel += w.scroll_y,
            else => {},
        };

        const keys = sdl3.keyboard.getState();
        const ctrl = keys[@intFromEnum(sdl3.Scancode.left_ctrl)] or
                     keys[@intFromEnum(sdl3.Scancode.right_ctrl)];

        // ── State Updates ─────────────────────────────────────────────────────
        if (tab or e_key) app.ui.set(.tool, 1 - app.ui.get(.tool));
        if (lbr) app.ui.set(.page, @max(0,                          app.ui.get(.page) - 1));
        if (rbr) app.ui.set(.page, @min(@as(i32, pages.len) - 1,    app.ui.get(.page) + 1));
        if (wheel != 0) {
            const w: i32 = @intFromFloat(wheel);
            if (ctrl) app.ui.set(.stab, std.math.clamp(app.ui.get(.stab) + w, 1, @as(i32, ring_cap)))
            else       app.ui.set(.size, std.math.clamp(app.ui.get(.size) + w, 1, 120));
        }

        // ── Commands ──────────────────────────────────────────────────────────
        if (ctrl  and z_key) app.popUndo();
        if (ctrl  and s_key) app.exportCanvas();
        if (!ctrl and c_key and app.canvas != null) app.clearCanvas();

        // ── Reactive Flush → Resize if canvas dimensions changed ──────────────
        const prev_cols = app.ui.get(.cols);
        const prev_rows = app.ui.get(.rows);
        _ = app.ui.flush();
        if (app.ui.get(.cols) != prev_cols or app.ui.get(.rows) != prev_rows)
            app.resizeCanvas();

        app.stroke();
        app.draw();
        ren.present() catch {};
    }
}
