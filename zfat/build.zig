const std = @import("std");

fn badConfig(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt ++ "\n", args);
    std.process.exit(1);
}

pub fn build(b: *std.Build) void {
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

    const target = b.resolveTargetQuery(target_query);
    const optimize = b.standardOptimizeOption(.{});
    const mod_options = b.addOptions();

    const config = blk: {
        var config = Config{};

        addConfigOption(b, &config, .read_only, "If set, the library will only be able to read filesystems.");
        addConfigOption(b, &config, .minimize, "Set this to different values to reduce API surface");
        addConfigOption(b, &config, .find, "Enable find support");
        addConfigOption(b, &config, .mkfs, "Enable mkfs support");
        addConfigOption(b, &config, .fastseek, "Use fast seek option");
        addConfigOption(b, &config, .expand, "Enables expandfs support");
        addConfigOption(b, &config, .chmod, "Enables chmod support");
        addConfigOption(b, &config, .label, "Enables support for handling of filesystem labels");
        addConfigOption(b, &config, .forward, "Enables forward support");
        addConfigOption(b, &config, .strfuncs, "Enables file string functions");
        addConfigOption(b, &config, .printf_lli, "Enables printf_lli support");
        addConfigOption(b, &config, .printf_float, "Enables printf_float support");
        addConfigOption(b, &config, .strf_encoding, "Sets the format string encoding");
        addConfigOption(b, &config, .max_long_name_len, "Sets the maximum name for long file names");
        addConfigOption(b, &config, .code_page, "Defines the OEM code page");
        addConfigOption(b, &config, .long_file_name, "Enables long file name support");
        addConfigOption(b, &config, .long_file_name_encoding, "Sets the encoding for long file names");
        addConfigOption(b, &config, .long_file_name_buffer_size, "Sets the buffer size for long file names");
        addConfigOption(b, &config, .short_file_name_buffer_size, "Sets the buffer size for short file names");
        addConfigOption(b, &config, .relative_path_api, "Enables the relative path API");
        addConfigOption(b, &config, .multi_partition, "Enables support for several partitions on the same drive");
        addConfigOption(b, &config, .lba64, "Enables support for 64 bit linear block addresses.");
        addConfigOption(b, &config, .min_gpt_sectors, "Sector count threshold for switching to GPT partition tables");
        addConfigOption(b, &config, .use_trim, "Enables support for ATA TRIM command");
        addConfigOption(b, &config, .tiny, "Enable tiny buffer configuration");
        addConfigOption(b, &config, .exfat, "Enables support for ExFAT");
        addConfigOption(b, &config, .filesystem_trust, "Sets which values in the FSINFO structure you trust.");
        addConfigOption(b, &config, .lock, "Enables file system locking");
        addConfigOption(b, &config, .reentrant, "Makes the library reentrant");
        addConfigOption(b, &config, .sync_type, "Defines the name of the C type which is used for sync operations");
        addConfigOption(b, &config, .timeout, "Defines the timeout period in OS ticks");

        const maybe_rtc_time = b.option([]const u8, "static-rtc", "Disables runtime time API by setting the clock to a fixed value. Provide a string in the format YYYY-MM-DD");
        if (maybe_rtc_time) |rtc_time| {
            const rtc_config = time: {
                if (rtc_time.len != 10)
                    break :time null;

                if ((rtc_time[4] != '-') or (rtc_time[7] != '-'))
                    break :time null;

                const year = std.fmt.parseInt(u16, rtc_time[0..4], 10) catch break :time null;
                const month = std.fmt.parseInt(u8, rtc_time[5..7], 10) catch break :time null;
                const day = std.fmt.parseInt(u8, rtc_time[8..10], 10) catch break :time null;

                break :time RtcConfig{
                    .static = .{
                        .year = year,
                        .month = std.meta.intToEnum(std.time.epoch.Month, month) catch break :time null,
                        .day = day,
                    },
                };
            };

            config.rtc = rtc_config orelse badConfig(
                "Invalid time format. Expected YYYY-MM-DD!",
                .{},
            );
        }

        const maybe_volume_count = b.option(u5, "volume-count", "Sets the total number of volumes. Mutually exclusive with -Dvolume-names");
        const maybe_volume_names = b.option([]const u8, "volume-names", "Sets the comma separated list of volume names. Mutually exclusive with -Dvolume-count");
        if ((maybe_volume_count != null) and (maybe_volume_names != null)) {
            badConfig("-Dvolume-count and -Dvolume-names are mutually exclusive.", .{});
        }

        if (maybe_volume_count) |volume_count| {
            config.volumes = .{ .count = volume_count };
        }

        if (maybe_volume_names) |volume_names| {
            var volumes = std.ArrayList([]const u8).init(b.allocator);

            var iter = std.mem.splitScalar(u8, volume_names, ',');
            while (iter.next()) |name| {
                volumes.append(name) catch @panic("out of memory");
            }
            config.volumes = .{ .named = volumes.items };
        }

        const maybe_sector_config = b.option([]const u8, "sector-size", "Defines the sector size range. Use `<min>:<max>` or `<fixed>`. Valid items for the range are 512, 1024, 2048 or 4096. No other values allowed.");
        if (maybe_sector_config) |sector_config| {
            if (std.mem.indexOfScalar(u8, sector_config, ':')) |split| {
                const min = sector_config[0..split];
                const max = sector_config[split + 1 ..];

                config.sector_size = .{
                    .dynamic = .{
                        .minimum = std.meta.stringToEnum(SectorOption, min) orelse badConfig(
                            "Invalid value for -Dsector-size: '{}'",
                            .{std.zig.fmtEscapes(sector_config)},
                        ),
                        .maximum = std.meta.stringToEnum(SectorOption, max) orelse badConfig(
                            "Invalid value for -Dsector-size: '{}'",
                            .{std.zig.fmtEscapes(sector_config)},
                        ),
                    },
                };
            } else {
                config.sector_size = .{
                    .static = std.meta.stringToEnum(SectorOption, sector_config) orelse badConfig(
                        "Invalid value for -Dsector-size: '{}'",
                        .{std.zig.fmtEscapes(sector_config)},
                    ),
                };
            }
        }

        // addConfigOption(b, &config, .sector_size, "");
        break :blk config;
    };

    mod_options.addOption(bool, "has_rtc", (config.rtc != .static));
    const zfat_lib = b.addStaticLibrary(.{
        .name = "zfat",
        .target = target,
        .optimize = optimize,
        .code_model = .default,
    });
    zfat_lib.installHeader(b.path("src/fatfs/ff.h"), "ff.h");
    zfat_lib.installHeader(b.path("src/fatfs/diskio.h"), "diskio.h");
    initializeMod(b, &zfat_lib.root_module, config);

    const zfat_mod = b.addModule("zfat", .{
        .root_source_file = b.path("src/fatfs.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .default,
    });
    initializeMod(b, zfat_mod, config);
    zfat_mod.addOptions("config", mod_options);
}

fn initializeMod(b: *std.Build, mod: *std.Build.Module, config: Config) void {
    mod.addIncludePath(b.path("src/fatfs"));
    mod.addCSourceFiles(.{
        .root = b.path("src/fatfs"),
        .files = &.{
            "ff.c",
            "ffunicode.c",
            "ffsystem.c",
            "memcmp.c",
            "memmove.c",
            "memset.c",
            "strcat.c",
            "strchr.c",
            "strcpy.c",
            "strlen.c",
        },
        .flags = &.{"-std=c99"},
    });
    applyPublicConfig(b, mod, config);
    applyPrivateConfig(b, mod, config);
    mod.link_libc = false;
}

fn applyPublicConfig(b: *std.Build, module: *std.Build.Module, config: Config) void {
    switch (config.volumes) {
        .count => |count| {
            module.addCMacro("FF_VOLUMES", b.fmt("{d}", .{count}));
            module.addCMacro("FF_STR_VOLUME_ID", "0");
        },
        .named => |strings| {
            var list = std.ArrayList(u8).init(b.allocator);
            for (strings) |name| {
                if (list.items.len > 0) {
                    list.appendSlice(", ") catch @panic("out of memory");
                }
                list.writer().print("\"{}\"", .{
                    std.fmt.fmtSliceHexUpper(name),
                }) catch @panic("out of memory");
            }

            module.addCMacro("FF_VOLUMES", b.fmt("{d}", .{strings.len}));
            module.addCMacro("FF_STR_VOLUME_ID", "1");
            module.addCMacro("FF_VOLUME_STRS", list.items);
        },
    }

    switch (config.sector_size) {
        .static => |size| {
            const str = b.fmt("{d}", .{@intFromEnum(size)});
            module.addCMacro("FF_MIN_SS", str);
            module.addCMacro("FF_MAX_SS", str);
        },
        .dynamic => |range| {
            module.addCMacro("FF_MIN_SS", b.fmt("{d}", .{@intFromEnum(range.minimum)}));
            module.addCMacro("FF_MAX_SS", b.fmt("{d}", .{@intFromEnum(range.maximum)}));
        },
    }
}

fn applyPrivateConfig(b: *std.Build, module: *std.Build.Module, config: Config) void {
    inline for (comptime std.meta.fields(Config)) |fld| {
        addConfigField(b, module, config, fld.name);
    }

    switch (config.rtc) {
        .dynamic => module.addCMacro("FF_FS_NORTC", "0"),
        .static => |date| {
            module.addCMacro("FF_FS_NORTC", "1");
            module.addCMacro("FF_NORTC_MON", b.fmt("{d}", .{date.month.numeric()}));
            module.addCMacro("FF_NORTC_MDAY", b.fmt("{d}", .{date.day}));
            module.addCMacro("FF_NORTC_YEAR", b.fmt("{d}", .{date.year}));
        },
    }
}

fn addConfigField(b: *std.Build, module: *std.Build.Module, config: Config, comptime field_name: []const u8) void {
    const value = @field(config, field_name);
    const Type = @TypeOf(value);
    const type_info = @typeInfo(Type);

    const str_value: []const u8 = if (Type == VolumeKind or Type == SectorSize or Type == RtcConfig)
        return // we don't emit these automatically
    else if (type_info == .Enum)
        b.fmt("{d}", .{@intFromEnum(value)})
    else if (type_info == .Int)
        b.fmt("{d}", .{value})
    else if (Type == bool)
        b.fmt("{d}", .{@intFromBool(value)})
    else if (Type == []const u8)
        value
    else {
        @compileError("Unsupported config type: " ++ @typeName(Type));
    };

    const macro_name = @field(macro_names, field_name);
    module.addCMacro(macro_name, str_value);
}

fn addConfigOption(b: *std.Build, config: *Config, comptime field: @TypeOf(.tag), desc: []const u8) void {
    const T = std.meta.FieldType(Config, field);

    @field(config, @tagName(field)) = b.option(T, @tagName(field), desc) orelse @field(config, @tagName(field));
}

pub const Config = struct {
    read_only: bool = false,
    minimize: MinimizeLevel = .default,
    find: bool = false,
    mkfs: bool = false,
    fastseek: bool = false,
    expand: bool = false,
    chmod: bool = false,
    label: bool = false,
    forward: bool = false,
    strfuncs: StringFuncConfig = .disabled,
    printf_lli: bool = false,
    printf_float: bool = false,
    strf_encoding: StrfEncoding = .oem,
    max_long_name_len: u8 = 255,
    code_page: CodePage = .us,
    long_file_name: bool = true,
    long_file_name_encoding: LfnEncoding = .oem,
    long_file_name_buffer_size: u32 = 255,
    short_file_name_buffer_size: u32 = 12,
    relative_path_api: RelativePathApi = .disabled,
    volumes: VolumeKind = .{ .count = 1 },
    sector_size: SectorSize = .{ .static = .@"512" },
    multi_partition: bool = false,
    lba64: bool = false,
    min_gpt_sectors: u32 = 0x10000000,
    use_trim: bool = false,
    tiny: bool = false,
    exfat: bool = false,
    rtc: RtcConfig = .{ .static = .{ .day = 1, .month = .jan, .year = 2024 } },
    filesystem_trust: Trust = .trust_all,
    lock: u32 = 0,
    reentrant: bool = false,

    sync_type: []const u8 = "HANDLE", // default to windows
    timeout: u32 = 1000,
};

pub const Trust = enum(u2) {
    // bit0=0: Use free cluster count in the FSINFO if available.
    // bit0=1: Do not trust free cluster count in the FSINFO.
    // bit1=0: Use last allocated cluster number in the FSINFO if available.
    // bit1=1: Do not trust last allocated cluster number in the FSINFO.

    trust_all = 0,
    trust_last_sector = 0b01,
    trust_free_clusters = 0b10,
    scan_all = 0b11,
};

pub const RtcConfig = union(enum) {
    dynamic,
    static: struct {
        day: u32,
        month: std.time.epoch.Month,
        year: u32,
    },
};

pub const VolumeKind = union(enum) {
    count: u5, // 1 … 10
    named: []const []const u8,
};

pub const SectorOption = enum(u32) {
    @"512" = 512,
    @"1024" = 1024,
    @"2048" = 2048,
    @"4096" = 4096,
};

pub const SectorSize = union(enum) {
    static: SectorOption,
    dynamic: struct {
        minimum: SectorOption,
        maximum: SectorOption,
    },
};

pub const RelativePathApi = enum(u2) {
    disabled = 0,
    enabed = 1,
    enabled_with_getcwd = 2,
};

pub const LfnEncoding = enum(u2) {
    oem = 0, // ANSI/OEM in current CP (TCHAR = char)
    utf16 = 1, // Unicode in UTF-16 (TCHAR = WCHAR)
    utf8 = 2, // Unicode in UTF-8 (TCHAR = char)
    utf32 = 3, // Unicode in UTF-32 (TCHAR = DWORD)
};

pub const StrfEncoding = enum(u2) {
    oem = 0,
    utf16_le = 1,
    utf16_be = 2,
    utf8 = 3,
};

pub const StringFuncConfig = enum(u2) {
    disabled = 0,
    enabled = 1,
    enabled_with_crlf = 2,
};

pub const MinimizeLevel = enum(u2) {
    default = 0,
    no_advanced = 1,
    no_dir_iteration = 2,
    no_lseek = 3,
};

const macro_names = struct {
    pub const read_only = "FF_FS_READONLY";
    pub const minimize = "FF_FS_MINIMIZE";
    pub const find = "FF_USE_FIND";
    pub const mkfs = "FF_USE_MKFS";
    pub const fastseek = "FF_USE_FASTSEEK";
    pub const expand = "FF_USE_EXPAND";
    pub const chmod = "FF_USE_CHMOD";
    pub const label = "FF_USE_LABEL";
    pub const forward = "FF_USE_FORWARD";
    pub const strfuncs = "FF_USE_STRFUNC";
    pub const printf_lli = "FF_PRINT_LLI";
    pub const printf_float = "FF_PRINT_FLOAT";
    pub const strf_encoding = "FF_STRF_ENCODE";
    pub const long_file_name = "FF_USE_LFN";
    pub const max_long_name_len = "FF_MAX_LFN";
    pub const code_page = "FF_CODE_PAGE";
    pub const long_file_name_encoding = "FF_LFN_UNICODE";
    pub const long_file_name_buffer_size = "FF_LFN_BUF";
    pub const short_file_name_buffer_size = "FF_SFN_BUF";
    pub const relative_path_api = "FF_FS_RPATH";
    pub const multi_partition = "FF_MULTI_PARTITION";
    pub const lba64 = "FF_LBA64";
    pub const min_gpt_sectors = "FF_MIN_GPT";
    pub const use_trim = "FF_USE_TRIM";
    pub const tiny = "FF_FS_TINY";
    pub const exfat = "FF_FS_EXFAT";
    pub const filesystem_trust = "FF_FS_NOFSINFO";
    pub const lock = "FF_FS_LOCK";
    pub const reentrant = "FF_FS_REENTRANT";
    pub const timeout = "FF_FS_TIMEOUT";
    pub const sync_type = "FF_SYNC_t";
};

pub const CodePage = enum(c_int) {
    dynamic = 0, // Include all code pages above and configured by f_setcp()

    us = 437,
    arabic_ms = 720,
    greek = 737,
    kbl = 771,
    baltic = 775,
    latin_1 = 850,
    latin_2 = 852,
    cyrillic = 855,
    turkish = 857,
    portuguese = 860,
    icelandic = 861,
    hebrew = 862,
    canadian_french = 863,
    arabic_ibm = 864,
    nordic = 865,
    russian = 866,
    greek_2 = 869,
    japanese_dbcs = 932,
    simplified_chinese_dbcs = 936,
    korean_dbcs = 949,
    traditional_chinese_dbcs = 950,
};
