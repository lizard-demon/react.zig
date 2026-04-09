const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
        
        // Enable all major SDL extensions
        .ext_image = true,
        .ext_net = true,
        .ext_ttf = true,
        .main = true, 

        // Static linkage
        .c_sdl_preferred_linkage = .static,
    });

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
            .{ .name = "sdl3", .module = sdl3.module("sdl3") },
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
