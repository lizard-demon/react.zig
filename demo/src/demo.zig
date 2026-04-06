const std = @import("std");
const rl   = @import("raylib");
const gl   = @import("raylib").gl;
const react = @import("react");

// ─────────────────────────────────────────────────────────────────────────────
//  Morton (display-only — no longer touches any pixel loop)
// ─────────────────────────────────────────────────────────────────────────────
inline fn part1By1(x_in: u32) u32 {
    var x = x_in & 0x0000_ffff;
    x = (x | (x <<  8)) & 0x00FF_00FF;
    x = (x | (x <<  4)) & 0x0F0F_0F0F;
    x = (x | (x <<  2)) & 0x3333_3333;
    x = (x | (x <<  1)) & 0x5555_5555;
    return x;
}
inline fn morton2D(x: u32, y: u32) u32 {
    return part1By1(x) | (part1By1(y) << 1);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reactive spec — purely spatial math, no render state
// ─────────────────────────────────────────────────────────────────────────────
const App = react.Signals(struct {
    pub const State = struct {
        mx:        i32 = 0,
        my:        i32 = 0,
        depth:     i32 = 5,
        max_depth: i32 = 8,  // 2^8 = 256 canvas side
    };

    pub const compute = struct {
        pub fn brush_px(s: struct { max_depth: i32, depth: i32 }) i32 {
            return @as(i32, 1) << @intCast(s.max_depth - s.depth);
        }

        pub fn cell_x(s: struct { mx: i32, brush_px: i32, depth: i32 }) i32 {
            const max = (@as(i32, 1) << @intCast(s.depth)) - 1;
            return std.math.clamp(@divTrunc(s.mx, s.brush_px), 0, max);
        }

        pub fn cell_y(s: struct { my: i32, brush_px: i32, depth: i32 }) i32 {
            const max = (@as(i32, 1) << @intCast(s.depth)) - 1;
            return std.math.clamp(@divTrunc(s.my, s.brush_px), 0, max);
        }

        // Recomputes only when cell_x/cell_y change — reactive, free on idle.
        pub fn morton_index(s: struct { cell_x: i32, cell_y: i32 }) u32 {
            return morton2D(@intCast(s.cell_x), @intCast(s.cell_y));
        }
    };
});

// ─────────────────────────────────────────────────────────────────────────────
//  One filled quad into whichever FBO is currently bound.
//
//  Mirrors raylib's DrawRectanglePro exactly:
//    - bind default white 1x1 texture so the batch sampler always has data
//    - emit normal + UVs that the default shader expects
//    - winding: TL -> BL -> BR -> TR  (CCW, matching rlgl batch layout)
//    - unbind texture so subsequent calls are not accidentally textured
//
//  Without these steps the batch may emit transparent or corrupted geometry
//  on some GL implementations, especially WebGL and older mobile drivers.
// ─────────────────────────────────────────────────────────────────────────────
inline fn paintQuad(x0: f32, y0: f32, size: f32, c: rl.Color) void {
    const x1 = x0 + size;
    const y1 = y0 + size;
    gl.rlSetTexture(gl.rlGetTextureIdDefault());
    gl.rlBegin(gl.rl_quads);
    gl.rlNormal3f(0.0, 0.0, 1.0);
    gl.rlColor4ub(c.r, c.g, c.b, c.a);
    gl.rlTexCoord2f(0.0, 0.0); gl.rlVertex2f(x0, y0); // TL
    gl.rlTexCoord2f(0.0, 1.0); gl.rlVertex2f(x0, y1); // BL
    gl.rlTexCoord2f(1.0, 1.0); gl.rlVertex2f(x1, y1); // BR
    gl.rlTexCoord2f(1.0, 0.0); gl.rlVertex2f(x1, y0); // TR
    gl.rlEnd();
    gl.rlSetTexture(0);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main
// ─────────────────────────────────────────────────────────────────────────────
pub fn main() void {
    const CANVAS_DIM:   i32 = 256;
    const CANVAS_SCALE: i32 = 2;
    const CANVAS_X:     i32 = 20;
    const CANVAS_Y:     i32 = 44;

    rl.initWindow(800, 600, "Morton Quadtree Painter — rlgl");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // GPU-resident canvas: FBO + colour attachment.
    // No CPU pixel buffer exists at any point in the program.
    const rt = rl.loadRenderTexture(CANVAS_DIM, CANVAS_DIM) catch unreachable;
    defer rl.unloadRenderTexture(rt);

    // Point-filter keeps pixel quads sharp at 2x scale.
    rl.setTextureFilter(rt.texture, .point);

    // Clear to black once via the FBO — not a memset, not a CPU loop.
    rl.beginTextureMode(rt);
    rl.clearBackground(rl.Color.black);
    rl.endTextureMode();

    var ui: App = .{};
    ui.dirty = std.math.maxInt(App.Dirty);
    _ = ui.flush();

    var active_color = rl.Color.ray_white;
    var scratch: [128]u8 = undefined;

    while (!rl.windowShouldClose()) {
        // ── Input ─────────────────────────────────────────────────────────
        const ms = rl.getMousePosition();
        ui.set(.mx, @intFromFloat((ms.x - @as(f32, @floatFromInt(CANVAS_X))) /
                                   @as(f32, @floatFromInt(CANVAS_SCALE))));
        ui.set(.my, @intFromFloat((ms.y - @as(f32, @floatFromInt(CANVAS_Y))) /
                                   @as(f32, @floatFromInt(CANVAS_SCALE))));

        const wheel = rl.getMouseWheelMove();
        if (wheel != 0) {
            const nd = ui.get(.depth) + @as(i32, @intFromFloat(wheel));
            ui.set(.depth, std.math.clamp(nd, 0, ui.get(.max_depth)));
        }

        if (rl.isKeyPressed(.one))   active_color = rl.Color.ray_white;
        if (rl.isKeyPressed(.two))   active_color = rl.Color.red;
        if (rl.isKeyPressed(.three)) active_color = rl.Color.green;
        if (rl.isKeyPressed(.four))  active_color = rl.Color.blue;

        // ── Reactive flush — only recomputes what changed ─────────────────
        _ = ui.flush();

        const cx: f32 = @floatFromInt(CANVAS_X);
        const cy: f32 = @floatFromInt(CANVAS_Y);
        const cs: f32 = @floatFromInt(CANVAS_DIM * CANVAS_SCALE);
        const in_bounds =
            ms.x >= cx and ms.x < cx + cs and
            ms.y >= cy and ms.y < cy + cs;

        // ── Paint — one rlgl quad directly into the GPU FBO ───────────────
        //
        // Entire write path:
        //   beginTextureMode  → bind FBO
        //   paintQuad         → one immediate-mode quad, batched by rlgl
        //   endTextureMode    → flush batch, unbind FBO
        //
        // Zero CPU copies. Zero texture uploads. Zero pixel loops.
        // The canvas state is owned by the GPU and never leaves it.
        if (in_bounds and rl.isMouseButtonDown(.left)) {
            const x0 = @as(f32, @floatFromInt(ui.get(.cell_x) * ui.get(.brush_px)));
            const y0 = @as(f32, @floatFromInt(ui.get(.cell_y) * ui.get(.brush_px)));
            const bp = @as(f32, @floatFromInt(ui.get(.brush_px)));

            rl.beginTextureMode(rt);
            paintQuad(x0, y0, bp, active_color);
            rl.endTextureMode();
        }

        // ── Render ────────────────────────────────────────────────────────
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.{ .r = 18, .g = 18, .b = 24, .a = 255 });

        // Blit canvas. Negative source height corrects the FBO Y-flip.
        // Entire read path: one textured quad to the screen. Done.
        rl.drawTexturePro(
            rt.texture,
            .{  // source — whole canvas, flipped vertically
                .x = 0, .y = 0,
                .width  = @as(f32, @floatFromInt(CANVAS_DIM)),
                .height = -@as(f32, @floatFromInt(CANVAS_DIM)),
            },
            .{  // dest — 2x scaled screen rect
                .x = @floatFromInt(CANVAS_X),
                .y = @floatFromInt(CANVAS_Y),
                .width  = @floatFromInt(CANVAS_DIM * CANVAS_SCALE),
                .height = @floatFromInt(CANVAS_DIM * CANVAS_SCALE),
            },
            .{ .x = 0, .y = 0 }, 0, rl.Color.white,
        );

        rl.drawRectangleLines(
            CANVAS_X - 1, CANVAS_Y - 1,
            CANVAS_DIM * CANVAS_SCALE + 2,
            CANVAS_DIM * CANVAS_SCALE + 2,
            rl.Color.dark_gray);

        // Brush preview
        if (in_bounds) {
            const bx = CANVAS_X + ui.get(.cell_x) * ui.get(.brush_px) * CANVAS_SCALE;
            const by = CANVAS_Y + ui.get(.cell_y) * ui.get(.brush_px) * CANVAS_SCALE;
            const bw = ui.get(.brush_px) * CANVAS_SCALE;
            rl.drawRectangleLinesEx(
                .{
                    .x = @floatFromInt(bx), .y = @floatFromInt(by),
                    .width = @floatFromInt(bw), .height = @floatFromInt(bw),
                }, 2.0, rl.Color.yellow);
        }

        // HUD
        rl.drawText("LINEAR QUADTREE PAINTER", 560, 44, 10, rl.Color.gray);
        rl.drawText(
            std.fmt.bufPrintZ(&scratch, "Depth: {d} / {d}",
                .{ ui.get(.depth), ui.get(.max_depth) }) catch "",
            560, 64, 20, rl.Color.ray_white);
        rl.drawText(
            std.fmt.bufPrintZ(&scratch, "Brush: {d}px",
                .{ ui.get(.brush_px) }) catch "",
            560, 94, 20, rl.Color.ray_white);
        rl.drawText(
            std.fmt.bufPrintZ(&scratch, "Morton: {d}",
                .{ ui.get(.morton_index) }) catch "",
            560, 124, 20, rl.Color.ray_white);
        rl.drawText("CONTROLS",             560, 220, 10, rl.Color.gray);
        rl.drawText("L-Click: Paint Quad",  560, 240, 16, rl.Color.light_gray);
        rl.drawText("Scroll: Change Depth", 560, 260, 16, rl.Color.light_gray);
        rl.drawText("1-4: Change Color",    560, 280, 16, rl.Color.light_gray);
    }
}
