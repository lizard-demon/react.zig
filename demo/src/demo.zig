const std   = @import("std");
const rl    = @import("raylib");
const react = @import("react");

// ─── Layout ───────────────────────────────────────────────────────────────────
const SIZES   = [_]i32{ 64, 128, 256, 512, 1024 };
const N_SIZES : i32 = SIZES.len;

const VIEWPORT : i32 = 560;                        // square canvas display area
const PAD      : i32 = 20;
const CTRL_X   : i32 = PAD + VIEWPORT + PAD;       // 600
const WIN_W    : i32 = CTRL_X + 260 + PAD;         // 880
const WIN_H    : i32 = PAD + VIEWPORT + PAD;        // 600

const BG    = rl.Color{ .r = 13,  .g = 13,  .b = 17,  .a = 255 };
const WELL  = rl.Color{ .r = 28,  .g = 28,  .b = 35,  .a = 255 };
const DIM   = rl.Color{ .r = 75,  .g = 75,  .b = 88,  .a = 255 };
const LABEL = rl.Color{ .r = 48,  .g = 48,  .b = 58,  .a = 255 };

// ─── Reactive spec ────────────────────────────────────────────────────────────
//
//  All layout math is declared once as a dependency graph.
//  flush() recomputes only what changed — idle frames touch nothing.
//
const App = react.Signals(struct {
    pub const State = struct {
        wi:      i32 = 2,   // SIZES index for canvas width  (default → 256 px)
        hi:      i32 = 2,   // SIZES index for canvas height (default → 256 px)
        brush_r: i32 = 8,   // brush radius in canvas pixels
    };
    pub const compute = struct {
        pub fn canvas_w(s: struct { wi: i32 }) i32 { return SIZES[@intCast(s.wi)]; }
        pub fn canvas_h(s: struct { hi: i32 }) i32 { return SIZES[@intCast(s.hi)]; }

        // Uniform scale: largest axis fills VIEWPORT exactly.
        pub fn scale(s: struct { canvas_w: i32, canvas_h: i32 }) f32 {
            return @as(f32, @floatFromInt(VIEWPORT)) /
                   @as(f32, @floatFromInt(@max(s.canvas_w, s.canvas_h)));
        }
        // Displayed canvas dimensions in screen pixels.
        pub fn disp_w(s: struct { canvas_w: i32, scale: f32 }) i32 {
            return @intFromFloat(@as(f32, @floatFromInt(s.canvas_w)) * s.scale);
        }
        pub fn disp_h(s: struct { canvas_h: i32, scale: f32 }) i32 {
            return @intFromFloat(@as(f32, @floatFromInt(s.canvas_h)) * s.scale);
        }
        // Canvas top-left in screen space, centred inside the viewport.
        pub fn off_x(s: struct { disp_w: i32 }) i32 {
            return PAD + @divTrunc(VIEWPORT - s.disp_w, 2);
        }
        pub fn off_y(s: struct { disp_h: i32 }) i32 {
            return PAD + @divTrunc(VIEWPORT - s.disp_h, 2);
        }
        // Brush radius in screen pixels — drives the live cursor ring.
        pub fn brush_sr(s: struct { brush_r: i32, scale: f32 }) f32 {
            return @as(f32, @floatFromInt(s.brush_r)) * s.scale;
        }
    };
});

// ─── Entry point ──────────────────────────────────────────────────────────────
pub fn main() void {
    rl.initWindow(WIN_W, WIN_H, "Draw");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var ui: App = .{};
    ui.dirty = std.math.maxInt(App.Dirty);
    _ = ui.flush();

    // Dirty-mask that covers canvas size changes (wi → canvas_w, hi → canvas_h).
    const size_mask = comptime App.watch(&.{ .canvas_w, .canvas_h });

    // GPU-resident canvas lives as an FBO.  No CPU pixel buffer exists.
    var rt: rl.RenderTexture2D = undefined;
    var rt_valid  = false;
    defer if (rt_valid) rl.unloadRenderTexture(rt);

    // Stroke state — tracks the previous sample point for capsule interpolation.
    var stroke_active = false;
    var prev_cx: f32  = 0;
    var prev_cy: f32  = 0;

    var should_clear = false;
    var scratch: [64]u8 = undefined;

    while (!rl.windowShouldClose()) {

        // ── Input ──────────────────────────────────────────────────────────
        if (rl.isKeyPressed(.left_bracket))  ui.set(.wi, @max(0,           ui.get(.wi) - 1));
        if (rl.isKeyPressed(.right_bracket)) ui.set(.wi, @min(N_SIZES - 1, ui.get(.wi) + 1));
        if (rl.isKeyPressed(.minus))         ui.set(.hi, @max(0,           ui.get(.hi) - 1));
        if (rl.isKeyPressed(.equal))         ui.set(.hi, @min(N_SIZES - 1, ui.get(.hi) + 1));
        if (rl.isKeyPressed(.c))             should_clear = true;

        const wheel = rl.getMouseWheelMove();
        if (wheel != 0)
            ui.set(.brush_r, std.math.clamp(
                ui.get(.brush_r) + @as(i32, @intFromFloat(wheel * 2)), 1, 200));

        // ── Reactive flush — only recomputes the changed subgraph ──────────
        const dirty = ui.flush();

        // ── (Re)create GPU canvas whenever canvas dimensions change ─────────
        //
        //  The dirty mask returned by flush() propagates downstream: changing
        //  wi sets wi | canvas_w | scale | disp_w | disp_h | off_x | off_y
        //  | brush_sr.  size_mask covers canvas_w and canvas_h plus their
        //  upstream (wi, hi), so any canvas-size event triggers recreation.
        //
        if (!rt_valid or dirty & size_mask != 0) {
            if (rt_valid) rl.unloadRenderTexture(rt);
            rt = rl.loadRenderTexture(ui.get(.canvas_w), ui.get(.canvas_h))
                catch unreachable;
            // Point filter: canvas pixels stay hard-edged at any scale.
            rl.setTextureFilter(rt.texture, .point);
            rl.beginTextureMode(rt);
            rl.clearBackground(rl.Color.black);
            rl.endTextureMode();
            rt_valid = true; stroke_active = false; should_clear = false;
        }
        if (should_clear) {
            rl.beginTextureMode(rt);
            rl.clearBackground(rl.Color.black);
            rl.endTextureMode();
            stroke_active = false; should_clear = false;
        }

        // ── Mouse → canvas coordinates ─────────────────────────────────────
        const ms   = rl.getMousePosition();
        const sc   = ui.get(.scale);
        const ox: f32 = @floatFromInt(ui.get(.off_x));
        const oy: f32 = @floatFromInt(ui.get(.off_y));
        const cx   = (ms.x - ox) / sc;
        const cy   = (ms.y - oy) / sc;
        const cw_f : f32 = @floatFromInt(ui.get(.canvas_w));
        const ch_f : f32 = @floatFromInt(ui.get(.canvas_h));
        const in_canvas = cx >= 0 and cx < cw_f and cy >= 0 and cy < ch_f;

        // ── Continuous capsule stroke ───────────────────────────────────────
        //
        //  Each frame while the button is held we paint a capsule from the
        //  previous sample to the current one: a thick line segment fills the
        //  gap, and a circle cap covers each endpoint.  This guarantees a
        //  perfectly smooth stroke at any mouse speed or frame rate — no gaps,
        //  no discrete quads.
        //
        //  All drawing happens inside beginTextureMode / endTextureMode so it
        //  lands directly on the GPU canvas FBO.  Nothing touches CPU memory.
        //
        const lmb = rl.isMouseButtonDown(.left);
        const rmb = rl.isMouseButtonDown(.right);
        const painting = (lmb or rmb) and in_canvas;
        const paint_col : rl.Color = if (rmb) rl.Color.black else rl.Color.white;
        const br : f32 = @floatFromInt(ui.get(.brush_r));

        if (painting) {
            rl.beginTextureMode(rt);
            if (stroke_active and (cx != prev_cx or cy != prev_cy)) {
                // Segment from previous sample to current — closes any inter-frame gap.
                rl.drawLineEx(
                    .{ .x = prev_cx, .y = prev_cy },
                    .{ .x = cx,      .y = cy },
                    br * 2.0, paint_col,
                );
                // Trailing cap rounds the segment end.
                rl.drawCircleV(.{ .x = prev_cx, .y = prev_cy }, br, paint_col);
            }
            // Leading cap / single dot on first touch.
            rl.drawCircleV(.{ .x = cx, .y = cy }, br, paint_col);
            rl.endTextureMode();
            prev_cx = cx; prev_cy = cy; stroke_active = true;
        } else if (!lmb and !rmb) {
            stroke_active = false;
        }

        // ── Render ─────────────────────────────────────────────────────────
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(BG);

        // Viewport well — subtle sunken area behind the canvas.
        rl.drawRectangle(PAD - 3, PAD - 3, VIEWPORT + 6, VIEWPORT + 6, WELL);

        // Canvas blit.  Negative source height corrects the FBO Y-flip.
        // This is the entire per-frame read path: one textured quad.
        rl.drawTexturePro(
            rt.texture,
            .{ .x = 0, .y = 0, .width = cw_f, .height = -ch_f },
            .{ .x      = ox,
               .y      = oy,
               .width  = @floatFromInt(ui.get(.disp_w)),
               .height = @floatFromInt(ui.get(.disp_h)) },
            .{ .x = 0, .y = 0 }, 0, rl.Color.white,
        );

        // Canvas border.
        rl.drawRectangleLines(
            ui.get(.off_x) - 1, ui.get(.off_y) - 1,
            ui.get(.disp_w) + 2, ui.get(.disp_h) + 2, LABEL,
        );

        // Cursor ring — follows brush size reactively via brush_sr.
        // Minimum 1.5 screen px so the ring stays visible on small brushes.
        if (in_canvas) {
            rl.hideCursor();
            const sr   = @max(ui.get(.brush_sr), 1.5);
            const scx  : i32 = @intFromFloat(ox + cx * sc);
            const scy  : i32 = @intFromFloat(oy + cy * sc);
            rl.drawCircleLines(scx, scy, sr,
                if (rmb)
                    rl.Color{ .r = 90,  .g = 170, .b = 255, .a = 180 }
                else
                    rl.Color{ .r = 210, .g = 210, .b = 210, .a = 180 });
            // Crosshair centre dot for sub-pixel precision.
            rl.drawPixel(scx, scy, rl.Color{ .r = 255, .g = 255, .b = 255, .a = 120 });
        } else {
            rl.showCursor();
        }

        // Vertical separator
        rl.drawLine(CTRL_X - 1, PAD, CTRL_X - 1, WIN_H - PAD, LABEL);

        // ── Controls panel ─────────────────────────────────────────────────
        const cpx = CTRL_X + 14;
        var   cpy : i32 = PAD + 6;

        rl.drawText("DRAW", cpx, cpy, 26, rl.Color.white);
        cpy += 42;

        // — Canvas size ——————————————————————————————————————————————————————
        rl.drawText("CANVAS", cpx, cpy, 9, LABEL);
        cpy += 15;

        // Width row: highlight the active size, dim the rest.
        rl.drawText("W", cpx, cpy, 13, DIM);
        for (SIZES, 0..) |sz, si| {
            const active = ui.get(.wi) == @as(i32, @intCast(si));
            rl.drawText(
                std.fmt.bufPrintZ(&scratch, "{d}", .{sz}) catch "",
                cpx + 18 + @as(i32, @intCast(si)) * 46, cpy, 13,
                if (active) rl.Color.white else DIM,
            );
        }
        cpy += 20;

        // Height row.
        rl.drawText("H", cpx, cpy, 13, DIM);
        for (SIZES, 0..) |sz, si| {
            const active = ui.get(.hi) == @as(i32, @intCast(si));
            rl.drawText(
                std.fmt.bufPrintZ(&scratch, "{d}", .{sz}) catch "",
                cpx + 18 + @as(i32, @intCast(si)) * 46, cpy, 13,
                if (active) rl.Color.white else DIM,
            );
        }
        cpy += 32;

        // — Brush ————————————————————————————————————————————————————————————
        rl.drawText("BRUSH", cpx, cpy, 9, LABEL);
        cpy += 15;
        rl.drawText(
            std.fmt.bufPrintZ(&scratch, "{d} px", .{ui.get(.brush_r)}) catch "",
            cpx, cpy, 20, rl.Color.white,
        );
        cpy += 30;
        // Preview circle: radius proportional to brush_r, capped at box size.
        {
            const BOX_R : f32 = 40.0;
            const bcx : i32 = cpx + 44;
            const bcy : i32 = cpy + 46;
            // Outer reference ring.
            rl.drawCircleLines(bcx, bcy, BOX_R, LABEL);
            // Inner filled circle scaled to brush size.
            const vis_r = @min(@as(f32, @floatFromInt(ui.get(.brush_r))) * 0.38, BOX_R);
            if (vis_r >= 0.5) rl.drawCircleV(
                .{ .x = @floatFromInt(bcx), .y = @floatFromInt(bcy) },
                vis_r, rl.Color.white,
            );
        }
        cpy += 104;

        // — Controls legend ——————————————————————————————————————————————————
        rl.drawText("CONTROLS", cpx, cpy, 9, LABEL);
        cpy += 17;
        const helps = [_][:0]const u8{
            "scroll      brush size",
            "L-click     paint",
            "R-click     erase",
            "[  ]        canvas W",
            "-  =        canvas H",
            "C           clear",
        };
        for (helps) |h| {
            rl.drawText(h, cpx, cpy, 12, DIM);
            cpy += 17;
        }

        // Canvas size readout at bottom of panel.
        cpy = WIN_H - PAD - 30;
        rl.drawText(
            std.fmt.bufPrintZ(&scratch, "{d} \xc3\x97 {d}",
                .{ ui.get(.canvas_w), ui.get(.canvas_h) }) catch "",
            cpx, cpy, 18, DIM,
        );
        cpy += 20;
        rl.drawText(
            std.fmt.bufPrintZ(&scratch, "{d} px canvas",
                .{ ui.get(.canvas_w) * ui.get(.canvas_h) }) catch "",
            cpx, cpy, 11, LABEL,
        );
    }
}
