const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast,
    });

    // const lib_mod = b.createModule(.{
    //     .root_source_file = b.path("src/root.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // exe_mod.addImport("zig_up_lib", lib_mod);

    // const lib = b.addLibrary(.{
    //     .linkage = .static,
    //     .name = "zig_up",
    //     .root_module = lib_mod,
    // });

    // b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "zigup",
        .root_module = exe_mod,
        .use_llvm = false,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
