const std = @import("std");

pub fn Framework(comptime State: type) type {
    return struct {
        const Self = @This();
        const Field = std.meta.FieldEnum(State);
        const FieldCount = std.meta.fields(State).len;
        const BitSet = std.StaticBitSet(FieldCount);

        _data: State = .{},
        
        dirty: struct {
            _bits: BitSet = BitSet.initEmpty(),

            pub fn get(self: @This(), comptime fields: anytype) bool {
                const T = @TypeOf(fields);
                switch (@typeInfo(T)) {
                    .@"struct" => |s| {
                        if (s.fields.len == 0) return self._bits.count() > 0;
                        inline for (s.fields) |f| {
                            const val = @field(fields, f.name);
                            if (self._bits.isSet(@intFromEnum(@as(Field, val)))) return true;
                        }
                    },
                    else => {}, // Catch-all for safety
                }
                return false;
            }

            pub fn set(self: *@This(), value: bool, comptime fields: anytype) void {
                const info = @typeInfo(@TypeOf(fields));
                if (info.@"struct".fields.len == 0) {
                    self._bits = if (value) BitSet.initFull() else BitSet.initEmpty();
                    return;
                }
                inline for (info.@"struct".fields) |f| {
                    const idx = @intFromEnum(@as(Field, @field(fields, f.name)));
                    if (value) self._bits.set(idx) else self._bits.unset(idx);
                }
            }
        } = .{},

        pub fn get(self: *const Self, comptime field: Field) std.meta.fieldInfo(State, field).type {
            return @field(self._data, @tagName(field));
        }

        pub fn set(self: *Self, comptime field: Field, value: std.meta.fieldInfo(State, field).type) void {
            self.dirty.set(false, .{}); 
            self.recurse(field, value, .{field});
            
            inline for (std.meta.fields(State)) |f| {
                const FEnum = @field(Field, f.name);
                if (self.dirty.get(.{FEnum})) {
                    const component = @field(self._data, f.name);
                    const TComp = @TypeOf(component);
                    if (@typeInfo(TComp) == .@"struct" and @hasDecl(TComp, "draw")) {
                        component.draw();
                    }
                }
            }
        }

        fn recurse(self: *Self, comptime field: Field, value: anytype, comptime visited: anytype) void {
            const current = @field(self._data, @tagName(field));
            if (!std.meta.eql(current, value)) {
                @field(self._data, @tagName(field)) = value;
                self.dirty._bits.set(@intFromEnum(field));

                if (@hasDecl(State, "react")) {
                    const Private = struct {
                        fw: *Self,
                        pub fn get(p: @This(), comptime f: Field) std.meta.fieldInfo(State, f).type { return p.fw.get(f); }
                        // Recursive Proxy also uses explicit typing for safety
                        pub fn set(p: @This(), comptime nf: Field, nv: std.meta.fieldInfo(State, nf).type) void {
                            inline for (visited) |prev| { if (nf == prev) @compileError("Cycle!"); }
                            p.fw.recurse(nf, nv, visited ++ .{nf});
                        }
                    };
                    State.react(Private{ .fw = self }, field);
                }
            }
        }
    };
}
