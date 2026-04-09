const std = @import("std");
pub fn Signals(comptime spec: type) type {

    // Extract Fields
    const State = blk: {
        const S = std.meta.fields(spec);
        const D = std.meta.declarations(spec);
        var fields: [S.len + D.len]std.builtin.Type.StructField = undefined;
        for (S, 0..) |f, i| fields[i] = f;
        for (D, 0..) |d, i| {
            if (@typeInfo(@TypeOf(@field(spec, d.name))) != .@"fn")
                @compileError("'" ++ d.name ++ "' - Do not declare values.");
            const T = @typeInfo(@TypeOf(@field(spec, d.name))).@"fn".return_type.?;
            fields[S.len + i] = .{
                .name = d.name,
                .type = T,
                .default_value_ptr = @ptrCast(&struct { const v: T = std.mem.zeroes(T); }.v),
                .is_comptime = false,
                .alignment = @alignOf(T) };
        }
        break :blk @Type(.{ .@"struct" = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = false } });
    };

    // Generate Field Enum
    const Tag = std.meta.FieldEnum(State);

    // Create DAG
    const Graph = blk: {
        const fields = std.meta.fields(State);
        const decls = std.meta.declarations(spec);
        @setEvalBranchQuota(1000 + (fields.len * fields.len * decls.len * 10));

        // Bitmask Map
        const Mask = std.StaticBitSet(fields.len);
        var direct = [_]Mask{Mask.initEmpty()} ** fields.len;
        var reach = [_]Mask{Mask.initEmpty()} ** fields.len;

        // Corrilate function paramiters with fields
        for (decls) |decl| {
            const idx = std.meta.fieldIndex(State, decl.name).?;
            const Params = @typeInfo(@TypeOf(@field(spec, decl.name))).@"fn".params[0].type.?;
            inline for (std.meta.fields(Params)) |p| direct[idx].set(std.meta.fieldIndex(State, p.name).?);
        }

        // Marks non-function fields as "visited"
        var visited = Mask.initEmpty();
        inline for (std.meta.fields(spec)) |f| {
            visited.set(std.meta.fieldIndex(State, f.name).?);
        }

        // Create DAG, recursively traversing from "visited" fields.
        var order: [decls.len]usize = undefined;
        for (0..decls.len) |i| {
            for (0..fields.len) |n| {
                if (visited.isSet(n) or !@hasDecl(spec, @tagName(@as(Tag, @enumFromInt(n))))) continue;
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

    // Return -> Graph + API
    return struct {
        const Self = @This();
        pub const Mask = Graph.Mask;
        state: State = .{},
        dirty: Mask = Mask.initEmpty(),

        // Field Access
        pub fn set(self: *Self, comptime tag: Tag, val: std.meta.fieldInfo(State, tag).type) void {
            if (std.meta.eql(@field(self.state, @tagName(tag)), val)) return;
            @field(self.state, @tagName(tag)) = val;
            self.dirty.set(@intFromEnum(tag));
        }
        pub fn get(self: *const Self, comptime tag: Tag) std.meta.fieldInfo(State, tag).type {
            return @field(self.state, @tagName(tag));
        }

        // Resolve Dirty Graph
        pub fn flush(self: *Self) Mask {
            if (self.dirty.count() == 0) return self.dirty;
            var out = self.dirty;
            inline for (Graph.order) |idx| {
                var intersection = Graph.direct[idx];
                intersection.setIntersection(out);
                if (intersection.count() != 0) {
                    const name = @tagName(@as(Tag, @enumFromInt(idx)));
                    const func = @field(spec, name);
                    const Args = @typeInfo(@TypeOf(func)).@"fn".params[0].type.?;
                    var args: Args = undefined;
                    inline for (std.meta.fields(Args)) |f| @field(args, f.name) = @field(self.state, f.name);
                    @field(self.state, name) = func(args);
                    out.set(idx);
                }
            }
            self.dirty = Mask.initEmpty();
            return out;
        }

        // Calculate transitive deps of field at comptime
        pub fn watch(comptime viewed: []const Tag) Mask {
            var m = Mask.initEmpty();
            for (viewed) |t| {
                m.set(@intFromEnum(t));
                m.setUnion(Graph.reach[@intFromEnum(t)]);
            }
            return m;
        }
    };
}
