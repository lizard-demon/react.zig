## react.zig

This is an ultra-minimalist reactive state framework for Zig 15.2.

Thus the tree is encoded within a recursion tree on a switch statement.

No runtime overhead. No DOM. No heap. No hidden metadata.

### Design Goals

* **Simplicity:** Clear, transparent data flow.
* **Safety:** Circular dependencies trigger `@compileError` during build.
* **Performance:** The dependancy tree is known ahead of time by the compiler.

---

### Usage

Define your state as a `struct`. Implement a `react` function with the following
type signature to define your dependency graph.

```zig
const State = struct {
    x: i32 = 0,
    y: i32 = 0,
    sum: i32 = 0,

    pub fn react(ui: anytype, comptime field: std.meta.FieldEnum(State)) void {
        switch (field) {
            .x, .y => ui.set(.sum, ui.get(.x) + ui.get(.y)),
            else => {},
        }
    }
};

```

Initialize the `Framework` and mutate state.

```zig
pub fn main() !void {
    var ui = Framework(State){};
    
    ui.set(.x, 10);
    ui.set(.y, 20);
    
    // Output: 30
    std.debug.print("{d}\n", .{ui.get(.sum)});
}

```

---

### How it Works

The framework utilizes **comptime recursion** with **dependency injection** on recursed calls for **cycle detection**.

1. **Static Dispatch:** When `ui.set(.x, val)` is called, the framework resolves the reaction path for `.x` at build time.
2. **Cycle Detection:** Every mutation path is traced. If you create a loop (), the build fails with a breadcrumb trail:
`error: Circular Dependency: x -> sum -> neg -> x`
3. **Hardware Efficiency:** Perfect for low-resource systems. The CPU executes direct stores and arithmetic without jumping through virtual tables or observer lists.

---

### API

* `ui.get(.field)`: Safe, constant-time state access.
* `ui.set(.field, value)`: Mutate state and trigger the downstream dependency chain.

