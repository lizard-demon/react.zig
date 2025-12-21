const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const react_dep = b.dependency("react_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/demo.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "react", .module = react_dep.module("react_zig") },
        },
    });

    const exe = b.addExecutable(.{
        .name = "ui_test",
        .root_module = mod,
    });

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    b.step("run", "Run the app").dependOn(&run.step);
}
