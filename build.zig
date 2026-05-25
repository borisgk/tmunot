const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "tmunot",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    // Link dynamic system library vips directly
    exe.root_module.linkSystemLibrary("vips", .{});
    exe.root_module.linkSystemLibrary("exif", .{});

    // Run minification and embedding script before compiling the executable
    const minify_cmd = b.addSystemCommand(&.{ "python3", "scripts/minify.py" });
    exe.step.dependOn(&minify_cmd.step);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
