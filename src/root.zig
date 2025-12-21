const std = @import("std");

pub fn Router(comptime State: type, comptime Logic: type, comptime Context: type) type {
    return struct {
        const sys = @This();
        const key = std.meta.FieldEnum(State);

        state: State = .{},
        ctx: Context,

        pub fn Event(comptime T: type) type {
            return struct {
                sys: *sys,
                ctx: *Context,
                key: key,
                old: T,
                new: T,

                pub fn emit(event: @This(), comptime k: key, v: std.meta.fieldInfo(State, k).type) void {
                    event.sys.set(k, v);
                }
            };
        }

        pub fn get(s: *const sys, comptime k: key) std.meta.fieldInfo(State, k).type {
            return @field(s.state, @tagName(k));
        }

        pub fn set(s: *sys, comptime k: key, v: std.meta.fieldInfo(State, k).type) void {
            const ptr = &@field(s.state, @tagName(k));
            const old = ptr.*;
            if (std.meta.eql(old, v)) return;
            ptr.* = v;
            
            if (@hasDecl(Logic, "route")) {
                const E = Event(@TypeOf(v));
                Logic.route(E{
                    .sys = s, 
                    .ctx = &s.ctx,
                    .key = k, 
                    .old = old, 
                    .new = v
                });
            }
        }
    };
}
