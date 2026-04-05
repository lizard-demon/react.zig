const std   = @import("std");
const rl    = @import("raylib");
const react = @import("react");

// ─────────────────────────────────────────────────────────────────────────────
//  Reactive spec
// ─────────────────────────────────────────────────────────────────────────────
const App = react.Signals(struct {
    pub const State = struct {
        // Sources
        red:    f32  = 0.47,
        green:  f32  = 0.78,
        blue:   f32  = 0.31,
        count:  i32  = 0,
        mode:   i32  = 0,   // 0=chill  1=party  2=zen
        time:   f32  = 0.0,
        // Derived
        luminance:   f32  = 0.0,
        doubled:     i32  = 0,
        quadrupled:  i32  = 0,
        is_even:     bool = true,
        ring_radius: f32  = 60.0,  // over-subscribed: mode + count + luminance
        bg_shade:    u8   = 18,
        pulse:       f32  = 0.8,   // over-subscribed: time + mode
    };

    pub const rules = .{
        .luminance   = .{ .red, .green, .blue },
        .doubled     = .{ .count },
        .quadrupled  = .{ .doubled },
        .is_even     = .{ .count },
        .ring_radius = .{ .mode, .count, .luminance },
        .bg_shade    = .{ .luminance },
        .pulse       = .{ .time, .mode },
    };

    const F = std.meta.FieldEnum(State);

    pub fn update(s: *State, comptime f: F) void {
        switch (f) {
            .luminance   => s.luminance   = 0.2126*s.red + 0.7152*s.green + 0.0722*s.blue,
            .doubled     => s.doubled     = s.count * 2,
            .quadrupled  => s.quadrupled  = s.doubled * 2,
            .is_even     => s.is_even     = @rem(s.count, 2) == 0,
            .ring_radius => s.ring_radius = switch (s.mode) {
                0    => 40.0 + s.luminance * 80.0,
                1    => 30.0 + @as(f32, @floatFromInt(@mod(s.count, 10))) * 8.0,
                else => 70.0,
            },
            .bg_shade => s.bg_shade = @intFromFloat(
                std.math.clamp(14.0 + s.luminance * 18.0, 0.0, 255.0)),
            .pulse => s.pulse = switch (s.mode) {
                1    => @sin(s.time * 6.0) * 0.5 + 0.5,
                2    => @sin(s.time * 1.0) * 0.3 + 0.7,
                else => @sin(s.time * 2.5) * 0.15 + 0.85,
            },
            else => {},
        }
    }
});

// ─────────────────────────────────────────────────────────────────────────────
//  Signal graph viz data
// ─────────────────────────────────────────────────────────────────────────────
const N_SIG = 13;
const N_SRC = 6;

const SIG_NAMES = [N_SIG][:0]const u8{
    "red","grn","blu","cnt","mod","time",
    "lum","x2","x4","evn","ring","bg","pls",
};
const SIG_ROW = [N_SIG]u1{ 0,0,0,0,0,0, 1,1,1,1,1,1,1 };
const SIG_X   = [N_SIG]f32{
     80,170,260,420,580,750,
    170,380,460,540,660,800,940,
};
const EDGES = [_][2]u8{
    .{0,6}, .{1,6},  .{2,6},
    .{3,7}, .{7,8},  .{3,9},
    .{4,10},.{3,10}, .{6,10},
    .{6,11},.{5,12}, .{4,12},
};

// ─────────────────────────────────────────────────────────────────────────────
//  Theme
// ─────────────────────────────────────────────────────────────────────────────
const PANEL   = rl.Color{ .r=26,  .g=28,  .b=38,  .a=255 };
const PANEL2  = rl.Color{ .r=38,  .g=42,  .b=58,  .a=255 };
const TXT     = rl.Color{ .r=200, .g=210, .b=230, .a=255 };
const DIM     = rl.Color{ .r=80,  .g=90,  .b=110, .a=255 };
const ACCENT  = rl.Color{ .r=80,  .g=170, .b=255, .a=255 };
const C_R     = rl.Color{ .r=240, .g=70,  .b=70,  .a=255 };
const C_G     = rl.Color{ .r=70,  .g=210, .b=110, .a=255 };
const C_Y     = rl.Color{ .r=255, .g=210, .b=60,  .a=255 };
const WHITE   = rl.Color{ .r=255, .g=255, .b=255, .a=255 };
const BG_DARK = rl.Color{ .r=12,  .g=12,  .b=18,  .a=255 };

// ─────────────────────────────────────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────────────────────────────────────
fn v2(x: f32, y: f32) rl.Vector2 { return .{ .x=x, .y=y }; }
fn rc(x: f32, y: f32, w: f32, h: f32) rl.Rectangle {
    return .{ .x=x, .y=y, .width=w, .height=h };
}
fn fi(v: f32) c_int { return @intFromFloat(v); }
fn hit(m: rl.Vector2, x: f32, y: f32, w: f32, h: f32) bool {
    return m.x>=x and m.x<=x+w and m.y>=y and m.y<=y+h;
}
fn toColor(r: f32, g: f32, b: f32) rl.Color {
    return .{
        .r = @intFromFloat(std.math.clamp(r*255, 0, 255)),
        .g = @intFromFloat(std.math.clamp(g*255, 0, 255)),
        .b = @intFromFloat(std.math.clamp(b*255, 0, 255)),
        .a = 255,
    };
}

fn z(buf: []u8, comptime fmt: []const u8, args: anytype) [:0]const u8 {
    return std.fmt.bufPrintZ(buf, fmt, args) catch "";
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main
// ─────────────────────────────────────────────────────────────────────────────
pub fn main() void {
    rl.initWindow(1100, 700, "Comptime Reactive Signals");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var ui: App   = .{};
    var drag: i32 = -1;
    var elapsed: f32 = 0;

    ui.dirty = std.math.maxInt(App.Dirty);
    _ = ui.flush();

    const SX: f32 = 75;
    const SW: f32 = 205;
    const SH: f32 = 14;
    const SY = [3]f32{ 118, 160, 202 };

    while (!rl.windowShouldClose()) {
        elapsed += rl.getFrameTime();
        const ms = rl.getMousePosition();
        const md = rl.isMouseButtonDown(.left);
        const mp = rl.isMouseButtonPressed(.left);

        // ── Input ─────────────────────────────────────────────────────────────
        ui.set(.time, elapsed);

        if (!md) {
            drag = -1;
        } else for (0..3) |si| {
            const sid: i32 = @intCast(si);
            const sy = SY[si];
            if (drag == sid or (drag == -1 and
                    ms.x >= SX-8 and ms.x <= SX+SW+8 and
                    ms.y >= sy-12 and ms.y <= sy+SH+12)) {
                drag = sid;
                const val = std.math.clamp((ms.x - SX) / SW, 0.0, 1.0);
                if (si == 0) ui.set(.red,   val);
                if (si == 1) ui.set(.green, val);
                if (si == 2) ui.set(.blue,  val);
                break;
            }
        }

        if (mp and hit(ms,368,162,54,36)) ui.set(.count, ui.get(.count) - 1);
        if (mp and hit(ms,538,162,54,36)) ui.set(.count, ui.get(.count) + 1);
        if (rl.isKeyPressed(.up))         ui.set(.count, ui.get(.count) + 1);
        if (rl.isKeyPressed(.down))       ui.set(.count, ui.get(.count) - 1);

        for (0..3) |mi| {
            const mx = 30.0 + @as(f32, @floatFromInt(mi)) * 110.0;
            if (mp and hit(ms, mx, 368, 90, 30)) ui.set(.mode, @intCast(mi));
        }
        if (rl.isKeyPressed(.one))   ui.set(.mode, 0);
        if (rl.isKeyPressed(.two))   ui.set(.mode, 1);
        if (rl.isKeyPressed(.three)) ui.set(.mode, 2);

        // ── Flush ─────────────────────────────────────────────────────────────
        const dirty = ui.flush();

        // ── Draw ──────────────────────────────────────────────────────────────
        rl.beginDrawing();
        defer rl.endDrawing();

        var b: [64]u8 = undefined;

        const bg = ui.get(.bg_shade);
        rl.clearBackground(.{ .r=bg, .g=bg, .b=bg+|8, .a=255 });

        const swatch = toColor(ui.get(.red), ui.get(.green), ui.get(.blue));

        // Title
        rl.drawRectangle(0, 0, 1100, 48, BG_DARK);
        rl.drawText("COMPTIME REACTIVE SIGNALS", 16, 14, 20, ACCENT);
        rl.drawText(z(&b, "{d} fps", .{rl.getFPS()}), 1024, 16, 16, DIM);

        // ── Color Mixer ───────────────────────────────────────────────────────
        rl.drawRectangleRounded(rc(20,68,300,260), 0.04, 8, PANEL);
        rl.drawText("COLOR MIXER", 36, 82, 14, DIM);

        const SCOL = [3]rl.Color{ C_R, C_G, .{.r=70,.g=130,.b=255,.a=255} };
        const SLBL = [3][:0]const u8{ "R", "G", "B" };
        const sval = [3]f32{ ui.get(.red), ui.get(.green), ui.get(.blue) };

        for (0..3) |si| {
            const sy  = SY[si];
            const val = sval[si];
            const col = SCOL[si];
            rl.drawText(SLBL[si], 42, fi(sy-2), 16, col);
            rl.drawRectangleRounded(rc(SX,sy,SW,SH), 0.5, 6, .{.r=18,.g=20,.b=28,.a=255});
            const fw = val * SW;
            if (fw > 1) rl.drawRectangleRounded(rc(SX,sy,fw,SH), 0.5, 6, rl.fade(col, 0.65));
            rl.drawCircleV(v2(SX+fw, sy+SH*0.5), SH*0.7, col);
            rl.drawCircleV(v2(SX+fw, sy+SH*0.5), SH*0.3, WHITE);
            rl.drawText(z(&b, "{d:.0}", .{val*255}), 290, fi(sy-1), 13, DIM);
        }

        rl.drawRectangleRounded(rc(40,238,120,22), 0.3, 6, swatch);
        rl.drawText(z(&b, "L = {d:.2}", .{ui.get(.luminance)}), 178, 240, 16,
            if (ui.get(.luminance) > 0.5) BG_DARK else WHITE);

        // ── Counter ───────────────────────────────────────────────────────────
        rl.drawRectangleRounded(rc(340,68,260,260), 0.04, 8, PANEL);
        rl.drawText("COUNTER", 356, 82, 14, DIM);

        {
            const t  = z(&b, "{d}", .{ui.get(.count)});
            const tw = rl.measureText(t, 44);
            rl.drawText(t, 470 - @divTrunc(tw, 2), 108, 44, WHITE);
        }

        inline for (.{ .{@as(f32,368), "-"}, .{@as(f32,538), "+"} }) |btn| {
            const bx  = btn[0];
            const hov = hit(ms, bx, 162, 54, 36);
            rl.drawRectangleRounded(rc(bx,162,54,36), 0.3, 6, if (hov) PANEL2 else PANEL);
            rl.drawRectangleRounded(rc(bx,162,54,36), 0.3, 6,
                rl.fade(ACCENT, if (hov) @as(f32,0.3) else @as(f32,0.08)));
            rl.drawText(btn[1], fi(bx+18), 167, 26, TXT);
        }

        rl.drawText(z(&b, "x2 = {d}", .{ui.get(.doubled)}),    370, 215, 20, ACCENT);
        rl.drawText(z(&b, "x4 = {d}", .{ui.get(.quadrupled)}), 370, 240, 20, ACCENT);
        rl.drawText(if (ui.get(.is_even)) "even" else "odd",   370, 272, 18,
            if (ui.get(.is_even)) C_G else C_R);

        // ── Reactive Ring ─────────────────────────────────────────────────────
        rl.drawRectangleRounded(rc(620,68,460,260), 0.04, 8, PANEL);
        rl.drawText("REACTIVE RING",     636, 82, 14, DIM);
        rl.drawText("(over-subscribed)", 776, 83, 11, rl.fade(C_Y, 0.5));

        const RCX: f32 = 850;
        const RCY: f32 = 200;
        const ring_r   = ui.get(.ring_radius);
        const pls      = ui.get(.pulse);

        for (0..6) |ri| {
            const f = @as(f32, @floatFromInt(ri));
            const r = @min(ring_r, 100.0) * 0.25 + f * 14.0;
            rl.drawRing(v2(RCX,RCY), r-1.5, r+1.5, 0, 360, 48,
                rl.fade(swatch, std.math.clamp(pls * (1.0 - f*0.14), 0.06, 1.0)));
        }
        for (0..8) |di| {
            const ang = elapsed*1.2 + @as(f32,@floatFromInt(di)) * std.math.pi*0.25;
            const orb = @min(ring_r, 100.0) * 0.25 + 42.0;
            rl.drawCircleV(v2(RCX+@cos(ang)*orb, RCY+@sin(ang)*orb), 2.5,
                rl.fade(swatch, pls*0.5));
        }
        rl.drawCircleV(v2(RCX,RCY), 6.0*pls, rl.fade(swatch, pls*0.7));
        rl.drawCircleV(v2(RCX,RCY), 3, WHITE);
        rl.drawText(z(&b, "r = {d:.0}", .{ring_r}), fi(RCX-16), fi(RCY+90), 13, DIM);

        // ── Mode Selector ─────────────────────────────────────────────────────
        rl.drawRectangleRounded(rc(20,340,1060,66), 0.03, 8, PANEL);
        rl.drawText("MODE", 36, 353, 14, DIM);

        const M_N = [3][:0]const u8{ "Chill", "Party", "Zen" };
        const M_C = [3]rl.Color{ ACCENT, C_Y, C_G };
        const cur: usize = @intCast(std.math.clamp(ui.get(.mode), 0, 2));

        for (0..3) |mi| {
            const mx  = 30.0 + @as(f32,@floatFromInt(mi)) * 110.0;
            const sel = mi == cur;
            const hov = hit(ms, mx, 368, 90, 30);
            rl.drawRectangleRounded(rc(mx,368,90,30), 0.3, 6,
                if (sel) M_C[mi] else if (hov) PANEL2 else rl.fade(PANEL2, 0.5));
            const tw = rl.measureText(M_N[mi], 16);
            rl.drawText(M_N[mi],
                fi(mx + (90.0 - @as(f32,@floatFromInt(tw))) * 0.5),
                fi(375), 16, if (sel) BG_DARK else DIM);
        }

        {
            const desc: [:0]const u8 = switch (cur) {
                0    => "ring = f(luminance)    pulse = gentle",
                1    => "ring = f(count % 10)   pulse = fast",
                else => "ring = 70 constant     pulse = breathe",
            };
            rl.drawText(desc, 370, 378, 13, rl.fade(M_C[cur], 0.6));
        }

        // ── Signal Propagation Graph ──────────────────────────────────────────
        const SGY: f32 = 418;
        rl.drawRectangleRounded(rc(20,SGY,1060,262), 0.03, 8, PANEL);
        rl.drawText("SIGNAL PROPAGATION", 36, fi(SGY+12), 14, DIM);
        // ↓ THE FIX: "{b:0>13}" not "{:0>13b}" — type before colon, options after
        rl.drawText(z(&b, "dirty  0b{b:0>13}", .{@as(u16,@intCast(dirty))}),
            840, fi(SGY+12), 12, rl.fade(ACCENT, 0.5));
        rl.drawText(z(&b, "{d}/{d} propagated", .{@popCount(dirty), N_SIG}),
            680, fi(SGY+12), 12, DIM);

        const ROW_Y = [2]f32{ SGY+55, SGY+135 };

        for (EDGES) |edge| {
            const x1   = SIG_X[edge[0]];
            const y1   = ROW_Y[SIG_ROW[edge[0]]];
            const x2   = SIG_X[edge[1]];
            const y2   = ROW_Y[SIG_ROW[edge[1]]];
            const live = dirty & (@as(App.Dirty,1) << @intCast(edge[0])) != 0;
            const col  = if (live) rl.fade(ACCENT, 0.35) else rl.fade(DIM, 0.12);
            const th: f32 = if (live) 2.0 else 1.0;
            if (SIG_ROW[edge[0]] == SIG_ROW[edge[1]]) {
                const mx = (x1+x2)*0.5;
                const my = y1+28;
                rl.drawLineEx(v2(x1,y1+8), v2(mx,my),   th, col);
                rl.drawLineEx(v2(mx,my),   v2(x2,y2+8), th, col);
            } else {
                rl.drawLineEx(v2(x1,y1+8), v2(x2,y2-8), th, col);
            }
        }

        for (0..N_SIG) |i| {
            const dx  = SIG_X[i];
            const dy  = ROW_Y[SIG_ROW[i]];
            const on  = dirty & (@as(App.Dirty,1) << @intCast(i)) != 0;
            const col = if (i < N_SRC) ACCENT else C_G;
            if (on) {
                rl.drawCircleV(v2(dx,dy), 9, rl.fade(col, 0.2));
                rl.drawCircleV(v2(dx,dy), 5, col);
            } else {
                rl.drawRing(v2(dx,dy), 3, 5, 0, 360, 16, rl.fade(col, 0.25));
            }
            rl.drawText(SIG_NAMES[i], fi(dx-10), fi(dy+12), 11, if (on) TXT else DIM);
        }

        rl.drawText("over-sub", fi(SIG_X[10]-16), fi(ROW_Y[1]+28), 10, rl.fade(C_Y,0.4));
        rl.drawText("over-sub", fi(SIG_X[12]-16), fi(ROW_Y[1]+28), 10, rl.fade(C_Y,0.4));
        rl.drawText("UP/DOWN  count    1/2/3  mode    drag  sliders",
            36, 668, 12, rl.fade(DIM, 0.4));
    }
}
