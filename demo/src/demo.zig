const std = @import("std");
const Signals = @import("react").Signals;

const Dashboard = Signals(struct {
    pub const State = struct {
        // --- Input Sources ---
        user_name: []const u8 = "Guest",
        price: f32 = 0.0,
        quantity: u32 = 0,
        tax_rate: f32 = 0.08, // 8%
        discount_rate: f32 = 0.10, // 10%

        // --- Derived Signals ---
        subtotal: f32 = 0.0,
        discount_amt: f32 = 0.0,
        total: f32 = 0.0,
        is_high_value: bool = false,
        summary_text: []const u8 = "",
    };

    pub const rules = .{
        .subtotal      = .{ .price, .quantity },
        .discount_amt  = .{ .subtotal, .discount_rate },
        .total         = .{ .subtotal, .discount_amt, .tax_rate },
        .is_high_value = .{ .total },
        .summary_text  = .{ .user_name, .total },
    };

    pub fn update(state: *State, comptime f: std.meta.FieldEnum(State)) void {
        switch (f) {
            .subtotal => state.subtotal = state.price * @as(f32, @floatFromInt(state.quantity)),
            .discount_amt => state.discount_amt = state.subtotal * state.discount_rate,
            .total => {
                const after_discount = state.subtotal - state.discount_amt;
                state.total = after_discount * (1.0 + state.tax_rate);
            },
            .is_high_value => state.is_high_value = (state.total > 500.0),
            .summary_text => {
                // In a real UI, this would use an allocator; here we use a static buffer for the demo
                state.summary_text = if (state.total > 0) "Order Ready" else "Cart Empty";
            },
            else => {},
        }
    }
});

// --- UI Components ---

fn renderHeader(app: *const Dashboard) void {
    std.debug.print("\n=== [ {s}'s Dashboard ] ===\n", .{app.get(.user_name)});
}

fn renderOrderDetails(app: *const Dashboard) void {
    std.debug.print("Price: ${d:.2} | Qty: {d} | Subtotal: ${d:.2}\n", .{
        app.get(.price), app.get(.quantity), app.get(.subtotal),
    });
}

fn renderTotal(app: *const Dashboard) void {
    const color = if (app.get(.is_high_value)) "\x1b[32;1m" else "\x1b[0m"; // Green if high value
    std.debug.print("Final Total: {s}${d:.2}\x1b[0m ({s})\n", .{
        color, app.get(.total), app.get(.summary_text),
    });
}

pub fn main() !void {
    var app: Dashboard = .{};
    
    // Component Watch Masks (Comptime resolved)
    const masks = .{
        .header = comptime Dashboard.watch(&.{.user_name}),
        .order  = comptime Dashboard.watch(&.{.subtotal}),
        .total  = comptime Dashboard.watch(&.{.total, .summary_text}),
    };

    // Initial Render
    renderHeader(&app);
    renderOrderDetails(&app);
    renderTotal(&app);

    // Simulated User Interaction: User changes name and quantity
    std.debug.print("\n> User updates name and adds items...\n", .{});
    
    app.set(.user_name, "Lizard");
    app.set(.price, 125.0);
    app.set(.quantity, 5);
    
    // The "Engine" Moment: Single flush propagates everything
    const dirty = app.flush();

    // Fine-grained Effect Dispatch: Only re-render what actually changed
    if (dirty & masks.header != 0) renderHeader(&app);
    if (dirty & masks.order != 0)  renderOrderDetails(&app);
    if (dirty & masks.total != 0)  renderTotal(&app);
}
