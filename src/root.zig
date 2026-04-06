const std = @import("std");

pub fn Signals(comptime Spec: type) type {

    // ── Synthesize the full state type at comptime ────────────────────────────
    // Sources come from Spec.State (user-declared, with their defaults).
    // Derived fields are appended: name from decl, type from return type,
    // default value is zero-initialized (overwritten on first flush).
    const FullState = comptime blk: {
        const src     = std.meta.fields(Spec.State);
        const derived = std.meta.declarations(Spec.compute);
        var fields: [src.len + derived.len]std.builtin.Type.StructField = undefined;

        for (src, 0..) |f, i| fields[i] = f;

        for (derived, 0..) |decl, i| {
            const fn_val = @field(Spec.compute, decl.name);
            const Ret    = @typeInfo(@TypeOf(fn_val)).@"fn".return_type orelse
                @compileError("compute." ++ decl.name ++ " must have an explicit return type");
            const zero: Ret = std.mem.zeroes(Ret);
            fields[src.len + i] = .{
                .name              = decl.name,
                .type              = Ret,
                .default_value_ptr = @ptrCast(&zero),   // ← renamed in 0.15
                .is_comptime       = false,
                .alignment         = @alignOf(Ret),
            };
        }

        break :blk @Type(.{ .@"struct" = .{
            .layout   = .auto,
            .fields   = &fields,
            .decls    = &.{},
            .is_tuple = false,
        }});
    };

    const N     = std.meta.fields(FullState).len;
    const Mask  = std.meta.Int(.unsigned, @max(N, 1));
    const Field = std.meta.FieldEnum(FullState);

    // ── Entire graph resolved at comptime ─────────────────────────────────────
    const reach, const order = comptime blk: {
        @setEvalBranchQuota(1000 + N * N * N * 10);

        // Dep masks: param struct field names are the dependencies.
        var direct = [_]Mask{0} ** N;
        for (std.meta.declarations(Spec.compute)) |decl| {
            const t      = std.meta.fieldIndex(FullState, decl.name) orelse
                @compileError("compute." ++ decl.name ++ " has no matching field in State");
            const fn_val = @field(Spec.compute, decl.name);
            const params = @typeInfo(@TypeOf(fn_val)).@"fn".params;
            if (params.len != 1)
                @compileError("compute." ++ decl.name ++ " must take exactly one struct argument");
            const DepType = params[0].type orelse
                @compileError("compute." ++ decl.name ++ " parameter must be a concrete type");
            for (std.meta.fields(DepType)) |df| {
                const dep = std.meta.fieldIndex(FullState, df.name) orelse
                    @compileError("dependency '" ++ df.name ++ "' not found in State");
                direct[t] |= @as(Mask, 1) << @intCast(dep);
            }
        }

        // Floyd–Warshall transitive closure.
        var trans = direct;
        for (0..N) |_| for (0..N) |i| for (0..N) |j| {
            if (trans[i] >> @intCast(j) & 1 == 1) trans[i] |= trans[j];
        };

        // Kahn topological sort.
        var sorted: [N]usize = undefined;
        var placed: Mask = 0;
        var k: usize = 0;
        while (k < N) {
            const prev = k;
            for (0..N) |i| {
                if (placed >> @intCast(i) & 1 == 0 and direct[i] & ~placed == 0) {
                    sorted[k] = i;
                    placed |= @as(Mask, 1) << @intCast(i);
                    k += 1;
                }
            }
            if (k == prev) @compileError("cycle in reactive graph");
        }
        break :blk .{ trans, sorted };
    };

    return struct {
        const Self = @This();
        pub const Dirty = Mask;

        state: FullState = .{},
        dirty: Mask      = 0,

        pub inline fn set(self: *Self, comptime f: Field, v: std.meta.fieldInfo(FullState, f).type) void {
            const ptr = &@field(self.state, @tagName(f));
            if (std.meta.eql(ptr.*, v)) return;
            ptr.* = v;
            self.dirty |= comptime @as(Mask, 1) << @intCast(@intFromEnum(f));
        }

        pub inline fn get(self: *const Self, comptime f: Field) std.meta.fieldInfo(FullState, f).type {
            return @field(self.state, @tagName(f));
        }

        pub fn flush(self: *Self) Mask {
            var d = self.dirty;
            if (d == 0) return 0;
            inline for (order) |idx| {
                const fname = comptime @tagName(@as(Field, @enumFromInt(idx)));
                if (comptime @hasDecl(Spec.compute, fname)) {
                    const m = comptime reach[idx];
                    if (m != 0 and d & m != 0) {
                        const fn_val  = @field(Spec.compute, fname);
                        const DepType = @typeInfo(@TypeOf(fn_val)).@"fn".params[0].type.?;
                        var deps: DepType = undefined;
                        inline for (std.meta.fields(DepType)) |df|
                            @field(deps, df.name) = @field(self.state, df.name);
                        @field(self.state, fname) = fn_val(deps);
                        d |= comptime @as(Mask, 1) << @intCast(idx);
                    }
                }
            }
            self.dirty = 0;
            return d;
        }

        pub fn watch(comptime watched: []const Field) Mask {
            comptime {
                var m: Mask = 0;
                for (watched) |f| {
                    const i = @intFromEnum(f);
                    m |= (@as(Mask, 1) << @intCast(i)) | reach[i];
                }
                return m;
            }
        }
    };
}
