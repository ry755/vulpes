const std = @import("std");
const Builder = std.build.Builder;
const LazyPath = std.build.LazyPath;
const zfat = @import("build_fatfs.zig");

pub fn build(b: *Builder) !void {
    // define a freestanding x86 cross-compilation target
    var target: std.zig.CrossTarget = .{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
    };

    // disable CPU features that require additional initialization
    // like MMX, SSE/2 and AVX. that requires us to enable the soft-float feature
    const Features = std.Target.x86.Feature;
    target.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
    target.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));

    // build the kernel itself
    const optimize = b.standardOptimizeOption(.{});
    const kernel = b.addExecutable(.{
        .name = "vulpes.elf",
        .root_source_file = .{ .path = "kernel/src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    kernel.code_model = .kernel;
    kernel.setLinkerScriptPath(.{ .path = "kernel/linker.ld" });
    kernel.addAssemblyFile(LazyPath.relative("kernel/src/boot.s"));
    zfat.build(b, kernel);
    b.getInstallStep().dependOn(&b.addInstallArtifact(kernel, .{
        .dest_dir = .{ .override = .{ .custom = "../base_image/boot/" } },
    }).step);
}
