const std = @import("std");

pub fn Framework(comptime State: type) type {
    return struct {
        const Self = @This();
        const Field = std.meta.FieldEnum(State);

        data: State = .{},

        pub fn get(self: *const Self, comptime field: Field) std.meta.fieldInfo(State, field).type {
            return @field(self.data, @tagName(field));
        }

        pub fn set(self: *Self, comptime field: Field, value: anytype) void {
            self.recurse(field, value, .{field});
        }

        fn recurse(self: *Self, comptime field: Field, value: anytype, comptime visited: anytype) void {
            @field(self.data, @tagName(field)) = value;
            if (@hasDecl(State, "react")) {
                const Private = struct {
                    fw: *Self,

                    pub fn get(c: @This(), comptime f: Field) std.meta.fieldInfo(State, f).type {
                        return c.fw.get(f);
                    }

                    pub fn set(c: @This(), comptime f: Field, val: anytype) void {
                        // inject dependency-check into set
                        inline for (visited) |prev| {
                            if (f == prev) {
                                // pretty error
                                const visited_str = comptime blk: {
                                    var res: []const u8 = "";
                                    for (visited) |node| {
                                        res = res ++ @tagName(node) ++ " -> ";
                                    }
                                    break :blk res;
                                };
                                @compileError("Circular Dependency: " ++ visited_str ++ @tagName(f));
                            }
                        }
                        // else set
                        c.fw.recurse(f, val, visited ++ .{f});
                    }
                };

                State.react(Private{ .fw = self }, field);
            }
        }
    };
}
