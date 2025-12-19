const std = @import("std");

pub fn Framework(comptime State: type, comptime Context: type) type {
    return struct {
        const Self = @This();
        const Field = std.meta.FieldEnum(State);
        const FCount = std.meta.fields(State).len;

        data: State = .{},
        dirty: std.StaticBitSet(FCount) = std.StaticBitSet(FCount).initEmpty(),
        ctx: Context,

        pub fn get(self: *const Self, comptime f: Field) std.meta.fieldInfo(State, f).type {
            return @field(self.data, @tagName(f));
        }

        pub fn set(self: *Self, comptime f: Field, v: std.meta.fieldInfo(State, f).type) void {
            self.dirty = std.StaticBitSet(FCount).initEmpty();
            self.recurse(f, v, .{f});
            inline for (std.meta.fields(State)) |info| {
                const f_enum = @field(Field, info.name);
                if (self.dirty.isSet(@intFromEnum(f_enum))) {
                    const comp = @field(self.data, info.name);
                    const TComp = @TypeOf(comp);
                    if (@typeInfo(TComp) == .@"struct" and @hasDecl(TComp, "react")) {
                        @field(self.data, info.name).react(&self.ctx);
                    }
                }
            }

            if (@hasDecl(Context, "react")) self.ctx.react(&self.data);
        }

        fn recurse(self: *Self, comptime f: Field, v: anytype, comptime visited: anytype) void {
            if (std.meta.eql(@field(self.data, @tagName(f)), v)) return;

            @field(self.data, @tagName(f)) = v;
            self.dirty.set(@intFromEnum(f));

            if (@hasDecl(State, "react")) {
                const Proxy = struct {
                    p: *Self,
                    pub fn get(c: @This(), comptime f2: Field) std.meta.fieldInfo(State, f2).type { 
                        return c.p.get(f2); 
                    }
                    pub fn set(c: @This(), comptime nf: Field, nv: std.meta.fieldInfo(State, nf).type) void {
                        inline for (visited) |prev| { 
                            if (nf == prev) @compileError("Circular Dependency: " ++ @tagName(nf)); 
                        }
                        c.p.recurse(nf, nv, visited ++ .{nf});
                    }
                };
                State.react(Proxy{ .p = self }, f);
            }
        }
    };
}
