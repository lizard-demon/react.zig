pub fn Store(comptime Data: type, comptime Logic: type, comptime Ctx: type) type {
    return struct {
        const Self = @This();
        const Field = std.meta.FieldEnum(Data);
        
        data: Data = .{},
        ctx: Ctx,
        dirty: bool = true,

        pub fn emit(s: *Self, comptime f: Field, v: std.meta.fieldInfo(Data, f).type) void {
            s.update(f, v, .{});
        }

        fn update(s: *Self, comptime f: Field, v: anytype, comptime path: anytype) void {
            const ptr = &@field(s.data, @tagName(f));
            if (std.meta.eql(ptr.*, v)) return;
            
            ptr.* = v;
            s.dirty = true;

            if (@hasDecl(Logic, "react")) {
                const Flow = struct {
                    _store: *Self,
                    data: *const Data,
                    ctx: *Ctx,
                    
                    pub fn emit(self: @This(), comptime f2: Field, v2: std.meta.fieldInfo(Data, f2).type) void {
                        inline for (path) |prev| {
                            if (f2 == prev) @compileError("Circular Dependency: " ++ @tagName(f2));
                        }
                        self._store.update(f2, v2, path ++ .{f});
                    }
                };
                Logic.react(Flow{ ._store=s, .data=&s.data, .ctx=&s.ctx }, f);
            }
        }

        pub fn handle(s: *Self) void {
            handleTree(&s.data, s, &s.ctx);
        }
    };
}
