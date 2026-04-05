const std = @import("std");

pub fn Signals(comptime Spec: type) type {
    const N     = std.meta.fields(Spec.State).len;
    const Mask  = std.meta.Int(.unsigned, @max(N, 1));
    const Field = std.meta.FieldEnum(Spec.State);

    // Entire graph resolved at comptime: direct deps → transitive closure → topo order.
    const reach, const order = comptime blk: {
        @setEvalBranchQuota(1000 + N * N * N * 10); // O(N³) Floyd–Warshall dominates

        // Parse declarative rules into per-node dependency bitmasks.
        var direct = [_]Mask{0} ** N;
        for (std.meta.fields(@TypeOf(Spec.rules))) |rf| {
            const t    = std.meta.fieldIndex(Spec.State, rf.name) orelse
                @compileError("rule '" ++ rf.name ++ "' has no matching State field");
            const rule = @field(Spec.rules, rf.name);
            for (std.meta.fields(@TypeOf(rule))) |df|
                direct[t] |= @as(Mask, 1) <<
                    @intCast(@intFromEnum(@as(Field, @field(rule, df.name))));
        }

        // Floyd–Warshall: reach[i] = bitmask of all transitive ancestors of i.
        // Over-subscription falls out naturally: each node's mask is the union
        // of all possible upstream paths, not just the runtime-active branch.
        var trans = direct;
        for (0..N) |_| for (0..N) |i| for (0..N) |j| {
            if (trans[i] >> @intCast(j) & 1 == 1) trans[i] |= trans[j];
        };

        // Kahn's algorithm: topo sort guarantees deps flush before dependents.
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

        state: Spec.State = .{},
        dirty: Mask = 0,

        // Equality-checked write; marks bit in dirty mask on change.
        pub inline fn set(self: *Self, comptime f: Field, v: std.meta.fieldInfo(Spec.State, f).type) void {
            const ptr = &@field(self.state, @tagName(f));
            if (std.meta.eql(ptr.*, v)) return;
            ptr.* = v;
            self.dirty |= comptime @as(Mask, 1) << @intCast(@intFromEnum(f));
        }

        pub inline fn get(self: *const Self, comptime f: Field) std.meta.fieldInfo(Spec.State, f).type {
            return @field(self.state, @tagName(f));
        }

        // Unrolled at comptime; each derived node costs one AND + branch at runtime.
        // Source nodes (reach == 0) are fully eliminated by the compiler.
        pub fn flush(self: *Self) Mask {
            var d = self.dirty;
            if (d == 0) return 0;
            inline for (order) |idx| {
                const m = comptime reach[idx];
                if (m != 0 and d & m != 0) {
                    Spec.update(&self.state, comptime @as(Field, @enumFromInt(idx)));
                    d |= comptime @as(Mask, 1) << @intCast(idx);
                }
            }
            self.dirty = 0;
            return d;
        }

        /// Comptime mask: watched fields + all transitive ancestors.
        /// Use against flush()'s return value for effect dispatch.
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
