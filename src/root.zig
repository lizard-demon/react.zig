const std = @import("std");

pub const Draw = @import("draw.zig");

pub fn Framework(comptime State: type, comptime Context: type) type {
    return struct {
        const Self = @This();
        const Field = std.meta.FieldEnum(State);

        data: State = .{},
        ctx: Context,

        pub fn get(self: *const Self, comptime f: Field) std.meta.fieldInfo(State, f).type {
            return @field(self.data, @tagName(f));
        }

        pub fn set(self: *Self, comptime f: Field, v: std.meta.fieldInfo(State, f).type) void {
            self.update(f, v, .{f});
            if (@hasDecl(Context, "react")) self.ctx.react(&self.data);
        }

        fn update(self: *Self, comptime f: Field, v: anytype, comptime path: anytype) void {
            const current = &@field(self.data, @tagName(f));
            
            // Change detection
            if (std.meta.eql(current.*, v)) return;
            current.* = v;

            if (@hasDecl(State, "react")) {
                const Proxy = struct {
                    p: *Self,
                    pub fn get(c: @This(), comptime f2: Field) std.meta.fieldInfo(State, f2).type {
                        return c.p.get(f2);
                    }
                    pub fn set(c: @This(), comptime nf: Field, nv: std.meta.fieldInfo(State, nf).type) void {
                        // Comptime cycle detection
                        inline for (path) |prev| {
                            if (nf == prev) @compileError("Circular Dependency: " ++ @tagName(nf));
                        }
                        c.p.update(nf, nv, path ++ .{nf});
                    }
                };
                State.react(Proxy{ .p = self }, f);
            }
        }
    };
}
