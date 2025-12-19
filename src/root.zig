const std = @import("std");
const react = @import("react");

pub fn Framework(comptime State: type) type {
    return struct {
        const Self = @This();
        const Field = std.meta.FieldEnum(State);
        const FieldCount = std.meta.fields(State).len;
        _data: State = .{},
        _dirty: std.StaticBitSet(FieldCount) = std.StaticBitSet(FieldCount).initEmpty(),

        pub fn dirty(self: *const Self, comptime fields: anytype) bool {
            const T = @TypeOf(fields);
            const info = @typeInfo(T);

            switch (info) {
                .@"struct" => |s| {
                    if (s.fields.len == 0) {
                        return self._dirty.count() > 0;
                    }

                    inline for (s.fields) |f| {
                        const field_val = @field(fields, f.name);
                        const actual_field = @as(Field, field_val);
                        if (self._dirty.isSet(@intFromEnum(actual_field))) return true;
                    }
                },
                else => @compileError("Expected a tuple or struct of fields, found " ++ @typeName(T)),
            }

            return false;
        }

        pub fn get(self: *const Self, comptime field: Field) std.meta.fieldInfo(State, field).type {
            return @field(self._data, @tagName(field));
        }

        pub fn set(self: *Self, comptime field: Field, value: anytype) void {
            self._dirty = std.StaticBitSet(FieldCount).initEmpty();
            self.recurse(field, value, .{field});
        }

        fn recurse(self: *Self, comptime field: Field, value: anytype, comptime visited: anytype) void {
            const current = @field(self._data, @tagName(field));
            
            // Only update and trigger reactions if the value actually changed
            if (!std.meta.eql(current, value)) {
                @field(self._data, @tagName(field)) = value;
                self._dirty.set(@intFromEnum(field));

                if (@hasDecl(State, "react")) {
                    // Dependency Inject a Cicular Dependency Checker
                    const Private = struct {
                        fw: *Self,
                        pub fn get(c: @This(), comptime f: Field) std.meta.fieldInfo(State, f).type {
                            return c.fw.get(f);
                        }
                        pub fn set(c: @This(), comptime next_f: Field, next_val: anytype) void {
                            inline for (visited) |prev| {
                                if (next_f == prev) @compileError("Circular Dependency: " ++ @tagName(next_f));
                            }
                            c.fw.recurse(next_f, next_val, visited ++ .{next_f});
                        }
                    };
                    State.react(Private{ .fw = self }, field);
                }
            }
        }

    };
}
