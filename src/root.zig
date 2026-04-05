const std = @import("std");

pub fn Signals(comptime Spec: type) type {
    const fields = std.meta.fields(Spec.State);
    const N      = fields.len;
    const Mask   = std.meta.Int(.unsigned, @max(N, 1));
    const Field  = std.meta.FieldEnum(Spec.State);

    const reach, const order = comptime blk: {
        // Scale quota to the dominant algorithm in this block.
        //   Floyd–Warshall transitive closure : O(N³)  ← dominant
        //   Kahn's topological sort           : O(N²)
        //   fieldIndex name scan per rule     : O(N)   (was stringToEnum → sort)
        // +1000 so the N=1 degenerate case never hits the default limit.
        @setEvalBranchQuota(1000 + N * N * N * 10);

        var direct = [_]Mask{0} ** N;

        // ── Parse rules → direct dependency bitmasks ──────────────────
        for (std.meta.fields(@TypeOf(Spec.rules))) |rf| {
            // fieldIndex: O(N) linear scan, no StaticStringMap, no sort.
            const t = std.meta.fieldIndex(Spec.State, rf.name) orelse
                @compileError("rule '" ++ rf.name ++ "' has no matching State field");
            const rule = @field(Spec.rules, rf.name);
            for (std.meta.fields(@TypeOf(rule))) |df|
                direct[t] |= @as(Mask, 1) <<
                    @intCast(@intFromEnum(@as(Field, @field(rule, df.name))));
        }

        // ── Floyd–Warshall: transitive closure ─────────────────────────
        var trans = direct;
        for (0..N) |_| for (0..N) |i| for (0..N) |j| {
            if (trans[i] >> @intCast(j) & 1 == 1) trans[i] |= trans[j];
        };

        // ── Kahn's: topological sort ───────────────────────────────────
        var sorted: [N]usize = undefined;
        var placed: Mask     = 0;
        var k: usize         = 0;
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

        state: Spec.State = .{},
        dirty: Mask       = 0,

        /// Write a source signal. Equality-checked: no-op if unchanged.
        pub inline fn set(
            self: *Self,
            comptime f: Field,
            v: std.meta.fieldInfo(Spec.State, f).type,
        ) void {
            const ptr = &@field(self.state, @tagName(f));
            if (std.meta.eql(ptr.*, v)) return;
            ptr.* = v;
            self.dirty |= comptime @as(Mask, 1) << @intCast(@intFromEnum(f));
        }

        pub inline fn get(
            self: *const Self,
            comptime f: Field,
        ) std.meta.fieldInfo(Spec.State, f).type {
            return @field(self.state, @tagName(f));
        }

        /// Propagate dirty signals through the topo-sorted graph.
        /// Returns full propagation mask (sources | recomputed derived).
        pub fn flush(self: *Self) Mask {
            var d = self.dirty;
            if (d == 0) return 0;
            inline for (order) |idx| {
                const m = comptime reach[idx];
                // m == 0  →  source node  →  branch eliminated at comptime
                // m != 0  →  one AND + jz at runtime
                if (m != 0 and d & m != 0) {
                    Spec.update(&self.state, comptime @as(Field, @enumFromInt(idx)));
                    d |= comptime @as(Mask, 1) << @intCast(idx);
                }
            }
            self.dirty = 0;
            return d;
        }

        /// Comptime mask covering watched fields + all transitive ancestors.
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
