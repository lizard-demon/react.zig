const std = @import("std");
const rl   = @import("raylib");
const react = @import("react");

// ─────────────────────────────────────────────────────────────────────────────
//  Reactive Spec
//  All spatial math lives here. flush() recomputes only what changed.
// ─────────────────────────────────────────────────────────────────────────────
const App = react.Signals(struct {
    pub const State = struct {
        mx:        i32 = 0,
        my:        i32 = 0,
        depth:     i32 = 5,
        max_depth: i32 = 8,   // 2^8 = 256 px canvas side
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

        // Morton index is display-only info; still reactive, zero cost when
        // cell_x/cell_y haven't changed.
        pub fn morton_index(s: struct { cell_x: i32, cell_y: i32 }) u32 {
            return morton2D(@intCast(s.cell_x), @intCast(s.cell_y));
        }
    };
});

// Morton (Z-Order) encode — used only for the UI readout now, not per-pixel.
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
//  Main
// ─────────────────────────────────────────────────────────────────────────────
pub fn main() void {
    const CANVAS_DIM   = 256;
    const CANVAS_SCALE = 2;
    const CANVAS_X     = 20;
    const CANVAS_Y     = 44;

    rl.initWindow(800, 600, "Morton Quadtree Painter");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // Single pixel buffer in row-major order.  No z_buffer needed.
    // We paint directly as rectangles; Morton is kept for the UI readout only.
    var pixels = [_]rl.Color{rl.Color.black} ** (CANVAS_DIM * CANVAS_DIM);

    const img = rl.Image{
        .data    = &pixels,
        .width   = CANVAS_DIM,
        .height  = CANVAS_DIM,
        .mipmaps = 1,
        .format  = .uncompressed_r8g8b8a8,
    };
    const texture = rl.loadTextureFromImage(img) catch unreachable;
    defer rl.unloadTexture(texture);

    var ui: App = .{};
    ui.dirty = std.math.maxInt(App.Dirty);
    _ = ui.flush();

    var active_color = rl.Color.ray_white;
    var canvas_dirty = false;   // only upload to GPU when something was drawn
    var scratch: [128]u8 = undefined;

    while (!rl.windowShouldClose()) {
        // ── Input ─────────────────────────────────────────────────────────
        const ms = rl.getMousePosition();
        ui.set(.mx, @intFromFloat((ms.x - CANVAS_X) / CANVAS_SCALE));
        ui.set(.my, @intFromFloat((ms.y - CANVAS_Y) / CANVAS_SCALE));

        const wheel = rl.getMouseWheelMove();
        if (wheel != 0) {
            const new_depth = ui.get(.depth) + @as(i32, @intFromFloat(wheel));
            ui.set(.depth, std.math.clamp(new_depth, 0, ui.get(.max_depth)));
        }

        if (rl.isKeyPressed(.one))   active_color = rl.Color.ray_white;
        if (rl.isKeyPressed(.two))   active_color = rl.Color.red;
        if (rl.isKeyPressed(.three)) active_color = rl.Color.green;
        if (rl.isKeyPressed(.four))  active_color = rl.Color.blue;

        // ── Reactive flush ────────────────────────────────────────────────
        _ = ui.flush();

        // ── Paint (only when mouse is down inside canvas) ─────────────────
        const in_bounds =
            ms.x >= CANVAS_X and ms.x < CANVAS_X + (CANVAS_DIM * CANVAS_SCALE) and
            ms.y >= CANVAS_Y and ms.y < CANVAS_Y + (CANVAS_DIM * CANVAS_SCALE);

        if (in_bounds and rl.isMouseButtonDown(.left)) {
            const cx: usize = @intCast(ui.get(.cell_x));
            const cy: usize = @intCast(ui.get(.cell_y));
            const bp: usize = @intCast(ui.get(.brush_px));

            // Fill the quad's pixel rectangle directly — no morton decode loop.
            // Complexity: O(brush_px²) rather than O(CANVAS_DIM²) every frame.
            for (cy * bp .. (cy + 1) * bp) |py|
                @memset(pixels[py * CANVAS_DIM + cx * bp ..][0..bp], active_color);

            canvas_dirty = true;
        }

        // ── GPU upload only when canvas changed ───────────────────────────
        if (canvas_dirty) {
            rl.updateTexture(texture, &pixels);
            canvas_dirty = false;
        }

        // ── Draw ──────────────────────────────────────────────────────────
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.{ .r = 18, .g = 18, .b = 24, .a = 255 });

        rl.drawTextureEx(texture, .{ .x = CANVAS_X, .y = CANVAS_Y },
            0, CANVAS_SCALE, rl.Color.white);
        rl.drawRectangleLines(
            CANVAS_X - 1, CANVAS_Y - 1,
            (CANVAS_DIM * CANVAS_SCALE) + 2, (CANVAS_DIM * CANVAS_SCALE) + 2,
            rl.Color.dark_gray);

        // Brush preview rectangle
        if (in_bounds) {
            const bx = CANVAS_X + (ui.get(.cell_x) * ui.get(.brush_px) * CANVAS_SCALE);
            const by = CANVAS_Y + (ui.get(.cell_y) * ui.get(.brush_px) * CANVAS_SCALE);
            const bw = ui.get(.brush_px) * CANVAS_SCALE;
            rl.drawRectangleLinesEx(
                .{ .x = @floatFromInt(bx), .y = @floatFromInt(by),
                   .width = @floatFromInt(bw), .height = @floatFromInt(bw) },
                2.0, rl.Color.yellow);
        }

        // HUD
        rl.drawText("LINEAR QUADTREE PAINTER", 560, 44, 10, rl.Color.gray);
        rl.drawText(
            std.fmt.bufPrintZ(&scratch, "Depth: {d} / {d}",
                .{ ui.get(.depth), ui.get(.max_depth) }) catch "",
            560, 64, 20, rl.Color.ray_white);
        rl.drawText(
            std.fmt.bufPrintZ(&scratch, "Brush: {d}px",
                .{ui.get(.brush_px)}) catch "",
            560, 94, 20, rl.Color.ray_white);
        rl.drawText(
            std.fmt.bufPrintZ(&scratch, "Morton: {d}",
                .{ui.get(.morton_index)}) catch "",
            560, 124, 20, rl.Color.ray_white);
        rl.drawText("CONTROLS", 560, 220, 10, rl.Color.gray);
        rl.drawText("L-Click: Paint Quad",   560, 240, 16, rl.Color.light_gray);
        rl.drawText("Scroll: Change Depth",  560, 260, 16, rl.Color.light_gray);
        rl.drawText("1-4: Change Color",     560, 280, 16, rl.Color.light_gray);
    }
}
