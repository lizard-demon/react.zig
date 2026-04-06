const std = @import("std");

// Internal API

fn buildState(comptime spec: type) type {
    const source = std.meta.fields(spec.State);
    const derive = std.meta.declarations(spec.compute);
    var fields: [source.len + derive.len]std.builtin.Type.StructField = undefined;

    for (source, 0..) |field, index| fields[index] = field;
    for (derive, 0..) |decl, index| {
        const func = @field(spec.compute, decl.name);
        const result = @typeInfo(@TypeOf(func)).@"fn".return_type orelse @compileError("missing return type");
        
        const Default = struct {
            const val: result = std.mem.zeroes(result);
        };

        fields[source.len + index] = .{
            .name = decl.name,
            .type = result,
            .default_value_ptr = @ptrCast(&Default.val),
            .is_comptime = false,
            .alignment = @alignOf(result),
        };
    }

    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    }});
}

fn buildGraph(comptime spec: type, comptime State: type) type {
    const count = std.meta.fields(State).len;
    const Mask = std.StaticBitSet(@max(count, 1));
    const Tag = std.meta.FieldEnum(State);
    const decl_len = std.meta.declarations(spec.compute).len;

    const Graph = comptime blk: {
        @setEvalBranchQuota(1000 + count * count * 10);

        var direct = [_]Mask{Mask.initEmpty()} ** count;
        for (std.meta.declarations(spec.compute)) |decl| {
            const target = std.meta.fieldIndex(State, decl.name).?;
            const func = @field(spec.compute, decl.name);
            const input = @typeInfo(@TypeOf(func)).@"fn".params[0].type.?;
            
            for (std.meta.fields(input)) |param| {
                const depend = std.meta.fieldIndex(State, param.name).?;
                direct[target].set(depend);
            }
        }

        var reach = direct;
        var flow: [decl_len]usize = undefined;
        var placed = Mask.initEmpty();
        var idx: usize = 0;
        var step: usize = 0;

        while (idx < count) {
            const prior = idx;
            for (0..count) |node| {
                if (!placed.isSet(node)) {
                    var overlap = direct[node];
                    overlap.setIntersection(placed);
                    
                    if (overlap.count() == direct[node].count()) {
                        placed.set(node);
                        
                        // Accumulate reachability
                        for (0..count) |dep| {
                            if (direct[node].isSet(dep)) {
                                reach[node].setUnion(reach[dep]);
                            }
                        }

                        const name = @tagName(@as(Tag, @enumFromInt(node)));
                        if (@hasDecl(spec.compute, name)) {
                            flow[step] = node;
                            step += 1;
                        }
                        idx += 1;
                    }
                }
            }
            if (idx == prior) @compileError("cycle detected");
        }

        break :blk .{ .direct = direct, .reach = reach, .flow = flow };
    };

    return struct {
        pub const Flags = Mask;
        pub const direct = Graph.direct;
        pub const reachability = Graph.reach;
        pub const evaluation_order = Graph.flow;
    };
}

// Public API

pub fn Signals(comptime spec: type) type {
    const State = buildState(spec);
    const Graph = buildGraph(spec, State);
    const Tag = std.meta.FieldEnum(State);

    return struct {
        const Self = @This();
        pub const Flags = Graph.Flags;

        state: State = .{},
        dirty: Flags = Flags.initEmpty(),

        pub inline fn set(self: *Self, comptime tag: Tag, value: std.meta.fieldInfo(State, tag).type) void {
            const ptr = &@field(self.state, @tagName(tag));
            if (std.meta.eql(ptr.*, value)) return;
            ptr.* = value;
            self.dirty.set(@intFromEnum(tag));
        }

        pub inline fn get(self: *const Self, comptime tag: Tag) std.meta.fieldInfo(State, tag).type {
            return @field(self.state, @tagName(tag));
        }

        pub fn flush(self: *Self) Flags {
            var flags = self.dirty;
            if (flags.count() == 0) return Flags.initEmpty();

            inline for (Graph.evaluation_order) |node| {
                const name = comptime @tagName(@as(Tag, @enumFromInt(node)));
                const direct_deps = comptime Graph.direct[node];

                var overlap = direct_deps;
                overlap.setIntersection(flags);

                // Only evaluate if a direct dependency was flagged
                if (overlap.count() > 0) {
                    const func = @field(spec.compute, name);
                    const input = @typeInfo(@TypeOf(func)).@"fn".params[0].type.?;
                    var deps: input = undefined;
                    
                    inline for (std.meta.fields(input)) |param| {
                        @field(deps, param.name) = @field(self.state, param.name);
                    }
                        
                    @field(self.state, name) = func(deps);
                    flags.set(node); // Cascades dirtiness to downstream nodes
                }
            }
            self.dirty = Flags.initEmpty();
            return flags;
        }

        pub fn watch(comptime viewed: []const Tag) Flags {
            comptime {
                var mask = Flags.initEmpty();
                for (viewed) |tag| {
                    mask.set(@intFromEnum(tag));
                    mask.setUnion(Graph.reachability[@intFromEnum(tag)]);
                }
                return mask;
            }
        }
    };
}
