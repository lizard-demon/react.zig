const std = @import("std");

pub fn Signals(comptime spec: type) type {

    const State = blk: {
        const S = std.meta.fields(spec.State);
        const D = std.meta.declarations(spec.compute);
        var fields: [S.len + D.len]std.builtin.Type.StructField = undefined;
        for (S, 0..) |f, i| fields[i] = f;
        for (D, 0..) |d, i| {
            const T = @typeInfo(@TypeOf(@field(spec.compute, d.name))).@"fn".return_type.?;
            fields[S.len + i] = .{ .name = d.name, .type = T, .default_value_ptr = @ptrCast(&struct { const v: T = std.mem.zeroes(T); }.v), .is_comptime = false, .alignment = @alignOf(T) };
        }
        break :blk @Type(.{ .@"struct" = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = false } });
    };

    const Tag = std.meta.FieldEnum(State);

    const Graph = blk: {
        const fields = std.meta.fields(State);
        const decls = std.meta.declarations(spec.compute);
        @setEvalBranchQuota(1000 + (fields.len * fields.len * decls.len * 10));

        const Mask = std.StaticBitSet(fields.len);
        var direct = [_]Mask{Mask.initEmpty()} ** fields.len;
        var reach = [_]Mask{Mask.initEmpty()} ** fields.len;
        
        // 1. Map dependencies
        for (decls) |decl| {
            const idx = std.meta.fieldIndex(State, decl.name).?;
            const Params = @typeInfo(@TypeOf(@field(spec.compute, decl.name))).@"fn".params[0].type.?;
            inline for (std.meta.fields(Params)) |p| direct[idx].set(std.meta.fieldIndex(State, p.name).?);
        }

        // 2. Initialize visited with base State fields (the "sources")
        var visited = Mask.initEmpty();
        inline for (std.meta.fields(spec.State)) |f| {
            visited.set(std.meta.fieldIndex(State, f.name).?);
        }

        // 3. Sort computed properties
        var order: [decls.len]usize = undefined;
        for (0..decls.len) |i| {
            for (0..fields.len) |n| {
                if (visited.isSet(n) or !@hasDecl(spec.compute, @tagName(@as(Tag, @enumFromInt(n))))) continue;
                
                if (direct[n].subsetOf(visited)) {
                    visited.set(n);
                    order[i] = n;
                    reach[n] = direct[n];
                    for (0..fields.len) |d| {
                        if (direct[n].isSet(d)) reach[n].setUnion(reach[d]);
                    }
                    break;
                }
            } else @compileError("Cycle or missing source detected");
        }
        break :blk .{ .Mask = Mask, .direct = direct, .reach = reach, .order = order };
    };

    return struct {
        const Self = @This();
        pub const Flags = Graph.Mask;

        state: State = .{},
        dirty: Flags = Flags.initEmpty(),

        pub fn set(self: *Self, comptime tag: Tag, val: std.meta.fieldInfo(State, tag).type) void {
            if (std.meta.eql(@field(self.state, @tagName(tag)), val)) return;
            @field(self.state, @tagName(tag)) = val;
            self.dirty.set(@intFromEnum(tag));
        }

        pub fn get(self: *const Self, comptime tag: Tag) std.meta.fieldInfo(State, tag).type {
            return @field(self.state, @tagName(tag));
        }

        pub fn flush(self: *Self) Flags {
            if (self.dirty.count() == 0) return self.dirty;
            var out = self.dirty;
            inline for (Graph.order) |idx| {
                var intersection = Graph.direct[idx];
                intersection.setIntersection(out);

                if (intersection.count() != 0) {
                    const name = @tagName(@as(Tag, @enumFromInt(idx)));
                    const func = @field(spec.compute, name);
                    const Args = @typeInfo(@TypeOf(func)).@"fn".params[0].type.?;
                    var args: Args = undefined;
                    inline for (std.meta.fields(Args)) |f| @field(args, f.name) = @field(self.state, f.name);
                    @field(self.state, name) = func(args);
                    out.set(idx);
                }
            }
            self.dirty = Flags.initEmpty();
            return out;
        }

        pub fn watch(comptime viewed: []const Tag) Flags {
            var m = Flags.initEmpty();
            for (viewed) |t| {
                m.set(@intFromEnum(t));
                m.setUnion(Graph.reach[@intFromEnum(t)]);
            }
            return m;
        }
    };
}
