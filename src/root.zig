const std = @import("std");

inline fn bit(comptime mask: type, comptime shift: usize) mask {
    return @as(mask, 1) << @intCast(shift);
}

pub fn Signals(comptime spec: type) type {
    const State = comptime blk: {
        const source = std.meta.fields(spec.State);
        const derive = std.meta.declarations(spec.compute);
        var fields: [source.len + derive.len]std.builtin.Type.StructField = undefined;
        for (source, 0..) |field, index| fields[index] = field;
        for (derive, 0..) |decl, index| {
            const func   = @field(spec.compute, decl.name);
            const result = @typeInfo(@TypeOf(func)).@"fn".return_type orelse
                @compileError("missing return type");
            var zero: result = std.mem.zeroes(result);
            fields[source.len + index] = .{
                .name              = decl.name,
                .type              = result,
                .default_value_ptr = @ptrCast(&zero),
                .is_comptime       = false,
                .alignment         = @alignOf(result),
            };
        }
        break :blk @Type(.{ .@"struct" = .{
            .layout   = .auto,
            .fields   = &fields,
            .decls    = &.{},
            .is_tuple = false,
        }});
    };

    const count = std.meta.fields(State).len;
    const Mask  = std.meta.Int(.unsigned, @max(count, 1));
    const Tag   = std.meta.FieldEnum(State);

    const reach, const order, const flow = comptime blk: {
        @setEvalBranchQuota(1000 + count * count * count * 10);

        var direct = [_]Mask{0} ** count;
        for (std.meta.declarations(spec.compute)) |decl| {
            const target = std.meta.fieldIndex(State, decl.name) orelse
                @compileError("missing field");
            const func   = @field(spec.compute, decl.name);
            const params = @typeInfo(@TypeOf(func)).@"fn".params;
            if (params.len != 1) @compileError("needs one param");
            const input  = params[0].type orelse @compileError("needs concrete type");
            for (std.meta.fields(input)) |param| {
                const depend = std.meta.fieldIndex(State, param.name) orelse
                    @compileError("missing dependency");
                direct[target] |= bit(Mask, depend);
            }
        }

        var paths = direct;
        for (0..count) |_| for (0..count) |row| for (0..count) |col| {
            if (paths[row] >> @intCast(col) & 1 == 1) paths[row] |= paths[col];
        };

        var sorted: [count]usize = undefined;
        var placed: Mask         = 0;
        var index: usize         = 0;
        while (index < count) {
            const prior = index;
            for (0..count) |node| {
                if (placed >> @intCast(node) & 1 == 0 and direct[node] & ~placed == 0) {
                    sorted[index] = node;
                    placed       |= bit(Mask, node);
                    index        += 1;
                }
            }
            if (index == prior) @compileError("cycle detected");
        }

        const length = std.meta.declarations(spec.compute).len;
        var subset: [length]usize = undefined;
        var step: usize           = 0;
        for (sorted) |node| {
            const name = @tagName(@as(Tag, @enumFromInt(node)));
            if (@hasDecl(spec.compute, name)) {
                subset[step] = node;
                step += 1;
            }
        }

        break :blk .{ paths, sorted, subset };
    };

    _ = order; 

    return struct {
        const Self = @This();
        pub const Flags = Mask;

        state: State = .{},
        dirty: Mask  = 0,

        pub inline fn set(self: *Self, comptime tag: Tag, value: std.meta.fieldInfo(State, tag).type) void {
            const ptr = &@field(self.state, @tagName(tag));
            if (std.meta.eql(ptr.*, value)) return;
            ptr.* = value;
            self.dirty |= bit(Mask, @intFromEnum(tag));
        }

        pub inline fn get(self: *const Self, comptime tag: Tag) std.meta.fieldInfo(State, tag).type {
            return @field(self.state, @tagName(tag));
        }

        pub fn flush(self: *Self) Mask {
            var flags = self.dirty;
            if (flags == 0) return 0;
            inline for (flow) |node| {
                const name = comptime @tagName(@as(Tag, @enumFromInt(node)));
                const mask = comptime reach[node];
                if (mask != 0 and flags & mask != 0) {
                    const func  = @field(spec.compute, name);
                    const input = @typeInfo(@TypeOf(func)).@"fn".params[0].type.?;
                    var deps: input = undefined;
                    inline for (std.meta.fields(input)) |param|
                        @field(deps, param.name) = @field(self.state, param.name);
                    @field(self.state, name) = func(deps);
                    flags |= bit(Mask, node);
                }
            }
            self.dirty = 0;
            return flags;
        }

        pub fn watch(comptime viewed: []const Tag) Mask {
            comptime {
                var mask: Mask = 0;
                for (viewed) |tag| mask |= bit(Mask, @intFromEnum(tag)) | reach[@intFromEnum(tag)];
                return mask;
            }
        }
    };
}
