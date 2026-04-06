const std   = @import("std");
const rl    = @import("raylib");
const react = @import("react");

// ─── Palette ─────────────────────────────────────────────────────────────────

const ink    = rl.Color.black;
const paper  = rl.Color.white;

const c_bg   = rl.Color{ .r = 18,  .g = 18,  .b = 22,  .a = 255 };
const c_well = rl.Color{ .r = 30,  .g = 30,  .b = 36,  .a = 255 };
const c_line = rl.Color{ .r = 46,  .g = 46,  .b = 54,  .a = 255 };
const c_dim  = rl.Color{ .r = 82,  .g = 82,  .b = 96,  .a = 255 };
const c_mute = rl.Color{ .r = 56,  .g = 56,  .b = 66,  .a = 255 };
const c_hi   = rl.Color.white;

// ─── Window ──────────────────────────────────────────────────────────────────

const vp    : i32 = 600;
const pad   : i32 = 16;
const side  : i32 = pad + vp + pad;
const win_w : i32 = side + 200 + pad;
const win_h : i32 = pad + vp + pad;

// ─── Pages  (B5 manga  ≈  5 ∶ 7) ────────────────────────────────────────────

const Page   = struct { w: i32, h: i32 };
const pages  = [_]Page{
    .{ .w = 210,  .h = 294  },   // XS  thumbnail
    .{ .w = 420,  .h = 588  },   // S   draft
    .{ .w = 630,  .h = 882  },   // M   standard
    .{ .w = 1050, .h = 1470 },   // L   high
    .{ .w = 1470, .h = 2058 },   // XL  print
};
const n_pg   : i32 = pages.len;
const pg_tag = [_][:0]const u8{ "XS", "S", "M", "L", "XL" };

// ─── Tuning ──────────────────────────────────────────────────────────────────

const ring_cap : usize = 16;    // stabiliser window
const snap_cap : usize = 20;    // undo depth

// ─── Reactive graph ──────────────────────────────────────────────────────────

const Ui = react.Signals(struct {
    pub const State = struct {
        page : i32 = 2,          // pages[] index
        size : i32 = 3,          // brush radius  canvas-px
        tool : i32 = 0,          // 0 pen   1 eraser
        stab : i32 = 6,          // stabiliser  1 … ring_cap
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

// ─── Undo ring ───────────────────────────────────────────────────────────────

fn snapPush(buf: *[snap_cap]?rl.Image, n: *usize, rt: rl.RenderTexture2D) void {
    const img = rl.loadImageFromTexture(rt.texture) catch return;
    if (n.* < snap_cap) { buf[n.*] = img; n.* += 1; return; }
    if (buf[0]) |old| rl.unloadImage(old);
    for (0..snap_cap - 1) |i| buf[i] = buf[i + 1];
    buf[snap_cap - 1] = img;
}

// ─── Entry ───────────────────────────────────────────────────────────────────

pub fn main() void {
    rl.initWindow(win_w, win_h, "Sumi");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var ui : Ui = .{};
    ui.dirty = std.math.maxInt(Ui.Flags);
    _ = ui.flush();

    const resized = comptime Ui.watch(&.{ .cols, .rows });

    // canvas
    var rt    : rl.RenderTexture2D = undefined;
    var rt_ok = false;
    defer if (rt_ok) rl.unloadRenderTexture(rt);

    // undo
    var snaps : [snap_cap]?rl.Image = [_]?rl.Image{null} ** snap_cap;
    var sn    : usize = 0;
    defer for (&snaps) |*s| if (s.*) |im| rl.unloadImage(im);

    // stabiliser ring  (pre-filled on each stroke start)
    var sr_x : [ring_cap]f32 = undefined;
    var sr_y : [ring_cap]f32 = undefined;
    var sr_i : usize = 0;

    // stroke
    var inking  = false;
    var last_x  : f32 = 0;
    var last_y  : f32 = 0;

    // flags
    var do_clear = false;
    var do_save  = false;
    var note     : [:0]const u8 = "";
    var note_t   : i32 = 0;
    var buf      : [128]u8 = undefined;

    // ─── loop ────────────────────────────────────────────────────────────────

    while (!rl.windowShouldClose()) {

        // ── input ──────────────────────────────────────────────────────
        const ctrl = rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control);

        if (rl.isKeyPressed(.tab) or rl.isKeyPressed(.e))
            ui.set(.tool, 1 - ui.get(.tool));
        if (rl.isKeyPressed(.left_bracket))
            ui.set(.page, @max(0, ui.get(.page) - 1));
        if (rl.isKeyPressed(.right_bracket))
            ui.set(.page, @min(n_pg - 1, ui.get(.page) + 1));

        const whl = rl.getMouseWheelMove();
        if (whl != 0) {
            if (ctrl)
                ui.set(.stab, std.math.clamp(
                    ui.get(.stab) + @as(i32, @intFromFloat(whl)),
                    1, @as(i32, ring_cap)))
            else
                ui.set(.size, std.math.clamp(
                    ui.get(.size) + @as(i32, @intFromFloat(whl)),
                    1, 120));
        }

        if (ctrl and rl.isKeyPressed(.z) and rt_ok and sn > 0) {
            sn -= 1;
            if (snaps[sn]) |snap| {
                rl.updateTexture(rt.texture, snap.data);
                rl.unloadImage(snap);
                snaps[sn] = null;
                inking = false;
            }
        }
        if (ctrl and rl.isKeyPressed(.s))  do_save  = true;
        if (!ctrl and rl.isKeyPressed(.c)) do_clear = true;

        // ── flush ──────────────────────────────────────────────────────
        const flags = ui.flush();

        // ── canvas lifecycle ───────────────────────────────────────────
        if (!rt_ok or flags & resized != 0) {
            for (&snaps) |*s| { if (s.*) |im| rl.unloadImage(im); s.* = null; }
            sn = 0;
            if (rt_ok) rl.unloadRenderTexture(rt);
            rt = rl.loadRenderTexture(ui.get(.cols), ui.get(.rows)) catch unreachable;
            rl.setTextureFilter(rt.texture, .point);
            rl.beginTextureMode(rt);
            rl.clearBackground(paper);
            rl.endTextureMode();
            rt_ok = true; inking = false; do_clear = false;
        }
        if (do_clear and rt_ok) {
            snapPush(&snaps, &sn, rt);
            rl.beginTextureMode(rt);
            rl.clearBackground(paper);
            rl.endTextureMode();
            inking = false; do_clear = false;
        }
        if (do_save and rt_ok) {
            var img = rl.loadImageFromTexture(rt.texture) catch unreachable;
            rl.imageFlipVertical(&img);
            _ = rl.exportImage(img, "sumi.png");
            rl.unloadImage(img);
            note = "exported  sumi.png"; note_t = 180;
            do_save = false;
        }

        // ── mapping ────────────────────────────────────────────────────
        const mp  = rl.getMousePosition();
        const z   = ui.get(.scale);
        const ofx : f32 = @floatFromInt(ui.get(.ox));
        const ofy : f32 = @floatFromInt(ui.get(.oy));
        const mx  = (mp.x - ofx) / z;
        const my  = (mp.y - ofy) / z;
        const cw  : f32 = @floatFromInt(ui.get(.cols));
        const ch  : f32 = @floatFromInt(ui.get(.rows));
        const hit = mx >= 0 and mx < cw and my >= 0 and my < ch;

        // ── stroke ─────────────────────────────────────────────────────
        const lmb    = rl.isMouseButtonDown(.left);
        const rmb    = rl.isMouseButtonDown(.right);
        const press  = (lmb or rmb) and hit;
        const erasing = rmb or (lmb and ui.get(.tool) == 1);
        const color  : rl.Color = if (erasing) paper else ink;
        const rad    : f32 = @floatFromInt(ui.get(.size));

        if (press) {
            if (!inking) {
                // ── stroke start: snapshot + prefill ring ──────────────
                snapPush(&snaps, &sn, rt);
                for (&sr_x) |*v| v.* = mx;
                for (&sr_y) |*v| v.* = my;
                sr_i = 0;

                rl.beginTextureMode(rt);
                rl.drawCircleV(.{ .x = mx, .y = my }, rad, color);
                rl.endTextureMode();
                last_x = mx; last_y = my; inking = true;
            } else {
                // ── stroke continue: feed ring → average → draw ───────
                sr_x[sr_i] = mx; sr_y[sr_i] = my;
                sr_i = (sr_i + 1) % ring_cap;

                const n  : usize = @intCast(ui.get(.stab));
                const nf : f32   = @floatFromInt(n);
                var sx : f32 = 0;
                var sy : f32 = 0;
                for (0..n) |i| {
                    const k = (sr_i + ring_cap - 1 - i) % ring_cap;
                    sx += sr_x[k]; sy += sr_y[k];
                }
                const qx = sx / nf;
                const qy = sy / nf;

                if (qx != last_x or qy != last_y) {
                    rl.beginTextureMode(rt);
                    rl.drawLineEx(
                        .{ .x = last_x, .y = last_y },
                        .{ .x = qx,     .y = qy },
                        rad * 2, color,
                    );
                    rl.drawCircleV(.{ .x = last_x, .y = last_y }, rad, color);
                    rl.drawCircleV(.{ .x = qx,     .y = qy },     rad, color);
                    rl.endTextureMode();
                    last_x = qx; last_y = qy;
                }
            }
        } else if (!lmb and !rmb) {
            inking = false;
        }

        // ── render ─────────────────────────────────────────────────────
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(c_bg);

        // well
        rl.drawRectangle(pad - 2, pad - 2, vp + 4, vp + 4, c_well);

        // canvas
        rl.drawTexturePro(
            rt.texture,
            .{ .x = 0, .y = 0, .width = cw, .height = -ch },
            .{ .x = ofx, .y = ofy,
               .width  = @floatFromInt(ui.get(.span)),
               .height = @floatFromInt(ui.get(.rise)) },
            .{ .x = 0, .y = 0 }, 0, c_hi,
        );
        rl.drawRectangleLines(
            ui.get(.ox) - 1, ui.get(.oy) - 1,
            ui.get(.span) + 2, ui.get(.rise) + 2, c_line);

        // cursor
        if (hit) {
            rl.hideCursor();
            const cr = @max(ui.get(.cur), 1.5);
            const cx : i32 = @intFromFloat(ofx + mx * z);
            const cy : i32 = @intFromFloat(ofy + my * z);
            const cc = if (erasing)
                rl.Color{ .r = 80, .g = 140, .b = 220, .a = 180 }
            else if (ui.get(.tool) == 1)
                rl.Color{ .r = 80, .g = 140, .b = 220, .a = 120 }
            else
                rl.Color{ .r = 180, .g = 180, .b = 180, .a = 170 };
            rl.drawCircleLines(cx, cy, cr, cc);
            rl.drawPixel(cx, cy,
                rl.Color{ .r = 200, .g = 200, .b = 200, .a = 100 });
        } else rl.showCursor();

        // divider
        rl.drawLine(side - 1, pad, side - 1, win_h - pad, c_line);

        // ── sidebar ────────────────────────────────────────────────────
        const px = side + 10;
        var py : i32 = pad + 4;

        rl.drawText("SUMI", px, py, 22, c_hi);
        py += 30;
        rl.drawLine(px, py, win_w - pad, py, c_line);
        py += 14;

        // tool
        rl.drawText("TOOL", px, py, 9, c_mute); py += 14;
        {
            const t = ui.get(.tool);
            rl.drawText("PEN",    px,      py, 14,
                if (t == 0) c_hi else c_dim);
            rl.drawText("ERASER", px + 56, py, 14,
                if (t == 1) c_hi else c_dim);
        }
        py += 26;

        // size
        rl.drawText("SIZE", px, py, 9, c_mute); py += 14;
        rl.drawText(
            std.fmt.bufPrintZ(&buf, "{d} px", .{ui.get(.size)}) catch "",
            px, py, 18, c_hi);
        py += 28;

        // brush preview
        {
            const bx = px + 36;
            const by = py + 36;
            rl.drawCircleLines(bx, by, 32, c_line);
            const vr = @min(
                @as(f32, @floatFromInt(ui.get(.size))) * 0.32, 32.0);
            if (vr >= 0.5)
                rl.drawCircleV(
                    .{ .x = @floatFromInt(bx), .y = @floatFromInt(by) },
                    vr, if (ui.get(.tool) == 0) ink else c_dim);
        }
        py += 82;

        // stabiliser
        rl.drawText("STABILIZER", px, py, 9, c_mute); py += 14;
        rl.drawText(
            std.fmt.bufPrintZ(&buf, "{d}", .{ui.get(.stab)}) catch "",
            px, py, 14, c_hi);
        {
            const bw : i32 = 110;
            const fw = @divTrunc(bw * ui.get(.stab), @as(i32, ring_cap));
            rl.drawRectangle(px + 24, py + 4, bw, 2, c_line);
            rl.drawRectangle(px + 24, py + 3, fw, 4, c_hi);
        }
        py += 24;

        // page
        rl.drawText("PAGE", px, py, 9, c_mute); py += 14;
        rl.drawText(
            std.fmt.bufPrintZ(&buf, "{d} \xc3\x97 {d}",
                .{ ui.get(.cols), ui.get(.rows) }) catch "",
            px, py, 14, c_hi);
        py += 18;
        for (pg_tag, 0..) |tag, i| {
            const on = ui.get(.page) == @as(i32, @intCast(i));
            rl.drawText(tag, px + @as(i32, @intCast(i)) * 32, py, 11,
                if (on) c_hi else c_dim);
        }
        py += 20;

        // undo
        rl.drawText(
            std.fmt.bufPrintZ(&buf, "undo  {d}/{d}", .{ sn, snap_cap }) catch "",
            px, py, 10, c_mute);
        py += 22;

        // keys
        rl.drawLine(px, py, win_w - pad, py, c_line); py += 10;
        rl.drawText("KEYS", px, py, 9, c_mute); py += 14;
        for ([_][:0]const u8{
            "scroll     brush size",
            "ctrl+scrl  stabilizer",
            "tab / E    tool",
            "[   ]      page size",
            "ctrl+Z     undo",
            "ctrl+S     export png",
            "C          clear",
        }) |line| {
            rl.drawText(line, px, py, 10, c_dim);
            py += 14;
        }

        // notification
        if (note_t > 0) {
            note_t -= 1;
            const a : u8 = if (note_t > 30) 220
                else @intCast(@min(note_t * 7, @as(i32, 220)));
            rl.drawText(note, pad + 4, win_h - pad - 16, 12,
                rl.Color{ .r = 170, .g = 200, .b = 255, .a = a });
        }
    }
}
