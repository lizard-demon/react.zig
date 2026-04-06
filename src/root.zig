const std = @import("std");

inline fn bit(comptime M: type, comptime i: usize) M {
    return @as(M, 1) << @intCast(i);
}

pub fn Signals(comptime Spec: type) type {
    const FullState = comptime blk: {
        const src     = std.meta.fields(Spec.State);
        const derived = std.meta.declarations(Spec.compute);
        var fields: [src.len + derived.len]std.builtin.Type.StructField = undefined;
        for (src, 0..) |f, i| fields[i] = f;
        for (derived, 0..) |decl, i| {
            const fn_val = @field(Spec.compute, decl.name);
            const Ret    = @typeInfo(@TypeOf(fn_val)).@"fn".return_type orelse
                @compileError("compute." ++ decl.name ++ " must have an explicit return type");
            var zero: Ret = std.mem.zeroes(Ret);
            fields[src.len + i] = .{
                .name              = decl.name,
                .type              = Ret,
                .default_value_ptr = @ptrCast(&zero),
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

    const reach, const order, const compute_order = comptime blk: {
        @setEvalBranchQuota(1000 + N * N * N * 10);

        // Build direct dependency masks from each compute fn's parameter struct.
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
                direct[t] |= bit(Mask, dep);
            }
        }

        // Floyd–Warshall transitive closure.
        var trans = direct;
        for (0..N) |_| for (0..N) |i| for (0..N) |j| {
            if (trans[i] >> @intCast(j) & 1 == 1) trans[i] |= trans[j];
        };

        // Kahn topological sort.
        var sorted: [N]usize   = undefined;
        var placed: Mask       = 0;
        var k: usize           = 0;
        while (k < N) {
            const prev = k;
            for (0..N) |i| {
                if (placed >> @intCast(i) & 1 == 0 and direct[i] & ~placed == 0) {
                    sorted[k] = i;
                    placed    |= bit(Mask, i);
                    k         += 1;
                }
            }
            if (k == prev) @compileError("cycle in reactive graph");
        }

        // Subset of sorted that are compute (derived) nodes only.
        const derived_len = std.meta.declarations(Spec.compute).len;
        var corder: [derived_len]usize = undefined;
        var ck: usize = 0;
        for (sorted) |idx| {
            const fname = @tagName(@as(Field, @enumFromInt(idx)));
            if (@hasDecl(Spec.compute, fname)) {
                corder[ck] = idx;
                ck += 1;
            }
        }

        break :blk .{ trans, sorted, corder };
    };

    _ = order; // available for callers who need the full sorted order

    return struct {
        const Self = @This();
        pub const Dirty = Mask;

        state: FullState = .{},
        dirty: Mask      = 0,

        pub inline fn set(self: *Self, comptime f: Field, v: std.meta.fieldInfo(FullState, f).type) void {
            const ptr = &@field(self.state, @tagName(f));
            if (std.meta.eql(ptr.*, v)) return;
            ptr.*      = v;
            self.dirty |= bit(Mask, @intFromEnum(f));
        }

        pub inline fn get(self: *const Self, comptime f: Field) std.meta.fieldInfo(FullState, f).type {
            return @field(self.state, @tagName(f));
        }

        pub fn flush(self: *Self) Mask {
            var d = self.dirty;
            if (d == 0) return 0;
            inline for (compute_order) |idx| {
                const fname   = comptime @tagName(@as(Field, @enumFromInt(idx)));
                const m       = comptime reach[idx];
                if (m != 0 and d & m != 0) {
                    const fn_val  = @field(Spec.compute, fname);
                    const DepType = @typeInfo(@TypeOf(fn_val)).@"fn".params[0].type.?;
                    var deps: DepType = undefined;
                    inline for (std.meta.fields(DepType)) |df|
                        @field(deps, df.name) = @field(self.state, df.name);
                    @field(self.state, fname) = fn_val(deps);
                    d |= bit(Mask, idx);
                }
            }
            self.dirty = 0;
            return d;
        }

        pub fn watch(comptime watched: []const Field) Mask {
            comptime {
                var m: Mask = 0;
                for (watched) |f| m |= bit(Mask, @intFromEnum(f)) | reach[@intFromEnum(f)];
                return m;
            }
        }
    };
}
