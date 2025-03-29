const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build) !void {
    // define a freestanding x86 cross-compilation target
    var target_query: std.Target.Query = .{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
    };

    // disable CPU features that require additional initialization
    // like MMX, SSE/2 and AVX. that requires us to enable the soft-float feature
    const Features = std.Target.x86.Feature;
    target_query.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
    target_query.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
    target_query.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
    target_query.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
    target_query.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
    target_query.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));

    // build the kernel itself
    const target = b.resolveTargetQuery(target_query);
    const optimize = b.standardOptimizeOption(.{});
    const kernel = b.addExecutable(.{
        .name = "vulpes.elf",
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "kernel/src/main.zig" } },
        .target = target,
        .optimize = optimize,
        .code_model = .default,
    });
    kernel.setLinkerScriptPath(.{ .src_path = .{ .owner = b, .sub_path = "kernel/linker.ld" } });
    kernel.addAssemblyFile(.{ .src_path = .{ .owner = b, .sub_path = "kernel/src/boot.s" } });

    const zfat_dep = b.dependency("zfat", .{
        .code_page = .us,
        .@"sector-size" = @as(u32, 512),
        .@"volume-count" = @as(u32, 2),
        // .@"volume-names" = @as([]const u8, "a,b,c,h,z"), // TODO(fqu): Requires VolToPart to be defined

        // Enable features:
        .find = true,
        .mkfs = true,
        .fastseek = true,
        .expand = true,
        .chmod = true,
        .label = true,
        .forward = true,
    });
    const zfat_mod = zfat_dep.module("zfat");
    kernel.root_module.addImport("zfat", zfat_mod);

    b.getInstallStep().dependOn(&b.addInstallArtifact(kernel, .{
        .dest_dir = .{ .override = .{ .custom = "../base_image/boot/" } },
    }).step);
}
