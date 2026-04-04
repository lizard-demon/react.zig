const std = @import("std");

/// Comptime-resolved fine-grained reactive signals.
/// Dependencies → transitive bitmasks → topological order, all at comptime.
/// Runtime flush is a flat bitmask scan: O(N) with zero allocations.
pub fn Signals(comptime Spec: type) type {
    const fields = std.meta.fields(Spec.State);
    const N = fields.len;
    const Mask = std.meta.Int(.unsigned, @max(N, 1));
    const Field = std.meta.FieldEnum(Spec.State);

    const reach, const order = comptime blk: {
        @setEvalBranchQuota(@max(1000, (N * N * N) + (N * N) + 1000));

        var direct = [_]Mask{0} ** N;

        // ── Parse declarative rules into direct dependency bitmasks ──
        for (std.meta.fields(@TypeOf(Spec.rules))) |rf| {
            const t = @intFromEnum(std.meta.stringToEnum(Field, rf.name).?);
            const rule = @field(Spec.rules, rf.name);
            for (std.meta.fields(@TypeOf(rule))) |df| {
                direct[t] |= @as(Mask, 1) <<
                    @intCast(@intFromEnum(@as(Field, @field(rule, df.name))));
            }
        }

        // ── Transitive closure: reach[i] = bitmask of ALL ancestors of i ──
        var trans = direct;
        for (0..N) |_| for (0..N) |i| for (0..N) |j| {
            if (trans[i] >> @intCast(j) & 1 == 1) trans[i] |= trans[j];
        };

        // ── Kahn's topological sort ──
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
        state: Spec.State = .{},
        dirty: Mask = 0,

        /// Set a source signal. O(1): write + OR one constant bit.
        pub inline fn set(self: *Self, comptime f: Field, v: std.meta.fieldInfo(Spec.State, f).type) void {
            @field(self.state, @tagName(f)) = v;
            self.dirty |= comptime @as(Mask, 1) << @intCast(@intFromEnum(f));
        }

        pub inline fn get(self: *const Self, comptime f: Field) std.meta.fieldInfo(Spec.State, f).type {
            return @field(self.state, @tagName(f));
        }

        /// Propagate dirty signals through topo-sorted graph.
        /// Each node: one AND to check, comptime-eliminated for sources.
        /// Returns dirty mask for effect dispatch.
        pub fn flush(self: *Self) Mask {
            const d = self.dirty;
            if (d == 0) return 0;
            inline for (order) |idx| {
                const m = comptime reach[idx];
                // m == 0 → source signal → entire branch comptime-eliminated
                // m != 0 → derived node → single `test reg, IMM` at runtime
                if (m != 0 and d & m != 0)
                    Spec.update(&self.state, comptime @as(Field, @enumFromInt(idx)));
            }
            self.dirty = 0;
            return d;
        }

        /// Comptime subscription mask: covers the watched fields
        /// and all their transitive ancestors. Use with flush() result.
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
