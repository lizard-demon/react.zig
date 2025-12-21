pub fn Store(comptime State: type, comptime Logic: type, comptime Ctx: type) type {
    return struct {
        const Sys = @This();
        const Key = std.meta.FieldEnum(State);
        
        state: State = .{},
        ctx: Ctx,
        dirty: bool = true, // Force initial render

        pub fn emit(s: *Sys, comptime k: Key, v: std.meta.fieldInfo(State, k).type) void {
            const ptr = &@field(s.state, @tagName(k));
            const old = ptr.*;
            if (std.meta.eql(old, v)) return;
            ptr.* = v;
            
            // DATA CHANGE -> INVALIDATE RENDER
            s.dirty = true;
            
            if (@hasDecl(Logic, "react")) Logic.react(.{ .sys=s, .ctx=&s.ctx, .key=k, .old=old, .new=v });
        }

        // Helper to check if we should redraw
        pub fn tick(s: *Sys) bool {
            // Layout must run if dirty to ensure hit-testing is accurate
            if (s.dirty) solve(&s.state);
            
            // Input pass: Checks for visual state changes (hover/press)
            // If interaction changes visuals, handle() sets s.dirty = true
            handle(&s.state, s, s.ctx.input);
            
            return s.dirty;
        }
    };
}
