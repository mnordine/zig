const std = @import("std.zig");
const mem = std.mem;
const Version = std.builtin.Version;

/// TODO Nearly all the functions in this namespace would be
/// better off if https://github.com/ziglang/zig/issues/425
/// was solved.
pub const Target = struct {
    cpu: Cpu,
    os: Os,
    abi: Abi,
    ofmt: ObjectFormat,

    pub const Os = struct {
        tag: Tag,
        version_range: VersionRange,

        pub const Tag = enum {
            freestanding,
            ananas,
            cloudabi,
            dragonfly,
            freebsd,
            fuchsia,
            ios,
            kfreebsd,
            linux,
            lv2,
            macos,
            netbsd,
            openbsd,
            solaris,
            windows,
            zos,
            haiku,
            minix,
            rtems,
            nacl,
            aix,
            cuda,
            nvcl,
            amdhsa,
            ps4,
            ps5,
            elfiamcu,
            tvos,
            watchos,
            driverkit,
            mesa3d,
            contiki,
            amdpal,
            hermit,
            hurd,
            wasi,
            emscripten,
            shadermodel,
            uefi,
            opencl,
            glsl450,
            vulkan,
            plan9,
            other,

            pub fn isDarwin(tag: Tag) bool {
                return switch (tag) {
                    .ios, .macos, .watchos, .tvos => true,
                    else => false,
                };
            }

            pub fn isBSD(tag: Tag) bool {
                return tag.isDarwin() or switch (tag) {
                    .kfreebsd, .freebsd, .openbsd, .netbsd, .dragonfly => true,
                    else => false,
                };
            }

            pub fn dynamicLibSuffix(tag: Tag) [:0]const u8 {
                if (tag.isDarwin()) {
                    return ".dylib";
                }
                switch (tag) {
                    .windows => return ".dll",
                    else => return ".so",
                }
            }

            pub fn defaultVersionRange(tag: Tag, arch: Cpu.Arch) Os {
                return .{
                    .tag = tag,
                    .version_range = VersionRange.default(tag, arch),
                };
            }
        };

        /// Based on NTDDI version constants from
        /// https://docs.microsoft.com/en-us/cpp/porting/modifying-winver-and-win32-winnt
        pub const WindowsVersion = enum(u32) {
            nt4 = 0x04000000,
            win2k = 0x05000000,
            xp = 0x05010000,
            ws2003 = 0x05020000,
            vista = 0x06000000,
            win7 = 0x06010000,
            win8 = 0x06020000,
            win8_1 = 0x06030000,
            win10 = 0x0A000000, //aka win10_th1
            win10_th2 = 0x0A000001,
            win10_rs1 = 0x0A000002,
            win10_rs2 = 0x0A000003,
            win10_rs3 = 0x0A000004,
            win10_rs4 = 0x0A000005,
            win10_rs5 = 0x0A000006,
            win10_19h1 = 0x0A000007,
            win10_vb = 0x0A000008, //aka win10_19h2
            win10_mn = 0x0A000009, //aka win10_20h1
            win10_fe = 0x0A00000A, //aka win10_20h2
            _,

            /// Latest Windows version that the Zig Standard Library is aware of
            pub const latest = WindowsVersion.win10_fe;

            /// Compared against build numbers reported by the runtime to distinguish win10 versions,
            /// where 0x0A000000 + index corresponds to the WindowsVersion u32 value.
            pub const known_win10_build_numbers = [_]u32{
                10240, //win10 aka win10_th1
                10586, //win10_th2
                14393, //win10_rs1
                15063, //win10_rs2
                16299, //win10_rs3
                17134, //win10_rs4
                17763, //win10_rs5
                18362, //win10_19h1
                18363, //win10_vb aka win10_19h2
                19041, //win10_mn aka win10_20h1
                19042, //win10_fe aka win10_20h2
            };

            /// Returns whether the first version `self` is newer (greater) than or equal to the second version `ver`.
            pub fn isAtLeast(self: WindowsVersion, ver: WindowsVersion) bool {
                return @enumToInt(self) >= @enumToInt(ver);
            }

            pub const Range = struct {
                min: WindowsVersion,
                max: WindowsVersion,

                pub fn includesVersion(self: Range, ver: WindowsVersion) bool {
                    return @enumToInt(ver) >= @enumToInt(self.min) and @enumToInt(ver) <= @enumToInt(self.max);
                }

                /// Checks if system is guaranteed to be at least `version` or older than `version`.
                /// Returns `null` if a runtime check is required.
                pub fn isAtLeast(self: Range, ver: WindowsVersion) ?bool {
                    if (@enumToInt(self.min) >= @enumToInt(ver)) return true;
                    if (@enumToInt(self.max) < @enumToInt(ver)) return false;
                    return null;
                }
            };

            /// This function is defined to serialize a Zig source code representation of this
            /// type, that, when parsed, will deserialize into the same data.
            pub fn format(
                self: WindowsVersion,
                comptime fmt: []const u8,
                _: std.fmt.FormatOptions,
                out_stream: anytype,
            ) !void {
                if (fmt.len > 0 and fmt[0] == 's') {
                    if (@enumToInt(self) >= @enumToInt(WindowsVersion.nt4) and @enumToInt(self) <= @enumToInt(WindowsVersion.latest)) {
                        try std.fmt.format(out_stream, ".{s}", .{@tagName(self)});
                    } else {
                        // TODO this code path breaks zig triples, but it is used in `builtin`
                        try std.fmt.format(out_stream, "@intToEnum(Target.Os.WindowsVersion, 0x{X:0>8})", .{@enumToInt(self)});
                    }
                } else {
                    if (@enumToInt(self) >= @enumToInt(WindowsVersion.nt4) and @enumToInt(self) <= @enumToInt(WindowsVersion.latest)) {
                        try std.fmt.format(out_stream, "WindowsVersion.{s}", .{@tagName(self)});
                    } else {
                        try std.fmt.format(out_stream, "WindowsVersion(0x{X:0>8})", .{@enumToInt(self)});
                    }
                }
            }
        };

        pub const LinuxVersionRange = struct {
            range: Version.Range,
            glibc: Version,

            pub fn includesVersion(self: LinuxVersionRange, ver: Version) bool {
                return self.range.includesVersion(ver);
            }

            /// Checks if system is guaranteed to be at least `version` or older than `version`.
            /// Returns `null` if a runtime check is required.
            pub fn isAtLeast(self: LinuxVersionRange, ver: Version) ?bool {
                return self.range.isAtLeast(ver);
            }
        };

        /// The version ranges here represent the minimum OS version to be supported
        /// and the maximum OS version to be supported. The default values represent
        /// the range that the Zig Standard Library bases its abstractions on.
        ///
        /// The minimum version of the range is the main setting to tweak for a target.
        /// Usually, the maximum target OS version will remain the default, which is
        /// the latest released version of the OS.
        ///
        /// To test at compile time if the target is guaranteed to support a given OS feature,
        /// one should check that the minimum version of the range is greater than or equal to
        /// the version the feature was introduced in.
        ///
        /// To test at compile time if the target certainly will not support a given OS feature,
        /// one should check that the maximum version of the range is less than the version the
        /// feature was introduced in.
        ///
        /// If neither of these cases apply, a runtime check should be used to determine if the
        /// target supports a given OS feature.
        ///
        /// Binaries built with a given maximum version will continue to function on newer
        /// operating system versions. However, such a binary may not take full advantage of the
        /// newer operating system APIs.
        ///
        /// See `Os.isAtLeast`.
        pub const VersionRange = union {
            none: void,
            semver: Version.Range,
            linux: LinuxVersionRange,
            windows: WindowsVersion.Range,

            /// The default `VersionRange` represents the range that the Zig Standard Library
            /// bases its abstractions on.
            pub fn default(tag: Tag, arch: Cpu.Arch) VersionRange {
                switch (tag) {
                    .freestanding,
                    .ananas,
                    .cloudabi,
                    .fuchsia,
                    .kfreebsd,
                    .lv2,
                    .zos,
                    .haiku,
                    .minix,
                    .rtems,
                    .nacl,
                    .aix,
                    .cuda,
                    .nvcl,
                    .amdhsa,
                    .ps4,
                    .ps5,
                    .elfiamcu,
                    .mesa3d,
                    .contiki,
                    .amdpal,
                    .hermit,
                    .hurd,
                    .wasi,
                    .emscripten,
                    .driverkit,
                    .shadermodel,
                    .uefi,
                    .opencl, // TODO: OpenCL versions
                    .glsl450, // TODO: GLSL versions
                    .vulkan,
                    .plan9,
                    .other,
                    => return .{ .none = {} },

                    .freebsd => return .{
                        .semver = Version.Range{
                            .min = .{ .major = 12, .minor = 0 },
                            .max = .{ .major = 13, .minor = 0 },
                        },
                    },
                    .macos => return switch (arch) {
                        .aarch64 => VersionRange{
                            .semver = .{
                                .min = .{ .major = 11, .minor = 7, .patch = 1 },
                                .max = .{ .major = 13, .minor = 0 },
                            },
                        },
                        .x86_64 => VersionRange{
                            .semver = .{
                                .min = .{ .major = 11, .minor = 7, .patch = 1 },
                                .max = .{ .major = 13, .minor = 0 },
                            },
                        },
                        else => unreachable,
                    },
                    .ios => return .{
                        .semver = .{
                            .min = .{ .major = 12, .minor = 0 },
                            .max = .{ .major = 13, .minor = 4, .patch = 0 },
                        },
                    },
                    .watchos => return .{
                        .semver = .{
                            .min = .{ .major = 6, .minor = 0 },
                            .max = .{ .major = 6, .minor = 2, .patch = 0 },
                        },
                    },
                    .tvos => return .{
                        .semver = .{
                            .min = .{ .major = 13, .minor = 0 },
                            .max = .{ .major = 13, .minor = 4, .patch = 0 },
                        },
                    },
                    .netbsd => return .{
                        .semver = .{
                            .min = .{ .major = 8, .minor = 0 },
                            .max = .{ .major = 9, .minor = 1 },
                        },
                    },
                    .openbsd => return .{
                        .semver = .{
                            .min = .{ .major = 6, .minor = 8 },
                            .max = .{ .major = 6, .minor = 9 },
                        },
                    },
                    .dragonfly => return .{
                        .semver = .{
                            .min = .{ .major = 5, .minor = 8 },
                            .max = .{ .major = 6, .minor = 0 },
                        },
                    },
                    .solaris => return .{
                        .semver = .{
                            .min = .{ .major = 5, .minor = 11 },
                            .max = .{ .major = 5, .minor = 11 },
                        },
                    },

                    .linux => return .{
                        .linux = .{
                            .range = .{
                                .min = .{ .major = 3, .minor = 16 },
                                .max = .{ .major = 5, .minor = 10, .patch = 81 },
                            },
                            .glibc = .{ .major = 2, .minor = 19 },
                        },
                    },

                    .windows => return .{
                        .windows = .{
                            .min = .win8_1,
                            .max = WindowsVersion.latest,
                        },
                    },
                }
            }
        };

        pub const TaggedVersionRange = union(enum) {
            none: void,
            semver: Version.Range,
            linux: LinuxVersionRange,
            windows: WindowsVersion.Range,
        };

        /// Provides a tagged union. `Target` does not store the tag because it is
        /// redundant with the OS tag; this function abstracts that part away.
        pub fn getVersionRange(self: Os) TaggedVersionRange {
            switch (self.tag) {
                .linux => return TaggedVersionRange{ .linux = self.version_range.linux },
                .windows => return TaggedVersionRange{ .windows = self.version_range.windows },

                .freebsd,
                .macos,
                .ios,
                .tvos,
                .watchos,
                .netbsd,
                .openbsd,
                .dragonfly,
                .solaris,
                => return TaggedVersionRange{ .semver = self.version_range.semver },

                else => return .none,
            }
        }

        /// Checks if system is guaranteed to be at least `version` or older than `version`.
        /// Returns `null` if a runtime check is required.
        pub fn isAtLeast(self: Os, comptime tag: Tag, version: anytype) ?bool {
            if (self.tag != tag) return false;

            return switch (tag) {
                .linux => self.version_range.linux.isAtLeast(version),
                .windows => self.version_range.windows.isAtLeast(version),
                else => self.version_range.semver.isAtLeast(version),
            };
        }

        /// On Darwin, we always link libSystem which contains libc.
        /// Similarly on FreeBSD and NetBSD we always link system libc
        /// since this is the stable syscall interface.
        pub fn requiresLibC(os: Os) bool {
            return switch (os.tag) {
                .freebsd,
                .netbsd,
                .macos,
                .ios,
                .tvos,
                .watchos,
                .dragonfly,
                .openbsd,
                .haiku,
                .solaris,
                => true,

                .linux,
                .windows,
                .freestanding,
                .ananas,
                .cloudabi,
                .fuchsia,
                .kfreebsd,
                .lv2,
                .zos,
                .minix,
                .rtems,
                .nacl,
                .aix,
                .cuda,
                .nvcl,
                .amdhsa,
                .ps4,
                .ps5,
                .elfiamcu,
                .mesa3d,
                .contiki,
                .amdpal,
                .hermit,
                .hurd,
                .wasi,
                .emscripten,
                .driverkit,
                .shadermodel,
                .uefi,
                .opencl,
                .glsl450,
                .vulkan,
                .plan9,
                .other,
                => false,
            };
        }
    };

    pub const aarch64 = @import("target/aarch64.zig");
    pub const arc = @import("target/arc.zig");
    pub const amdgpu = @import("target/amdgpu.zig");
    pub const arm = @import("target/arm.zig");
    pub const avr = @import("target/avr.zig");
    pub const bpf = @import("target/bpf.zig");
    pub const csky = @import("target/csky.zig");
    pub const hexagon = @import("target/hexagon.zig");
    pub const m68k = @import("target/m68k.zig");
    pub const mips = @import("target/mips.zig");
    pub const msp430 = @import("target/msp430.zig");
    pub const nvptx = @import("target/nvptx.zig");
    pub const powerpc = @import("target/powerpc.zig");
    pub const riscv = @import("target/riscv.zig");
    pub const sparc = @import("target/sparc.zig");
    pub const spirv = @import("target/spirv.zig");
    pub const s390x = @import("target/s390x.zig");
    pub const ve = @import("target/ve.zig");
    pub const wasm = @import("target/wasm.zig");
    pub const x86 = @import("target/x86.zig");

    pub const Abi = enum {
        none,
        gnu,
        gnuabin32,
        gnuabi64,
        gnueabi,
        gnueabihf,
        gnux32,
        gnuilp32,
        code16,
        eabi,
        eabihf,
        android,
        musl,
        musleabi,
        musleabihf,
        muslx32,
        msvc,
        itanium,
        cygnus,
        coreclr,
        simulator,
        macabi,
        pixel,
        vertex,
        geometry,
        hull,
        domain,
        compute,
        library,
        raygeneration,
        intersection,
        anyhit,
        closesthit,
        miss,
        callable,
        mesh,
        amplification,

        pub fn default(arch: Cpu.Arch, target_os: Os) Abi {
            if (arch.isWasm()) {
                return .musl;
            }
            switch (target_os.tag) {
                .freestanding,
                .ananas,
                .cloudabi,
                .dragonfly,
                .lv2,
                .solaris,
                .zos,
                .minix,
                .rtems,
                .nacl,
                .aix,
                .cuda,
                .nvcl,
                .amdhsa,
                .ps4,
                .ps5,
                .elfiamcu,
                .mesa3d,
                .contiki,
                .amdpal,
                .hermit,
                .other,
                => return .eabi,
                .openbsd,
                .freebsd,
                .fuchsia,
                .kfreebsd,
                .netbsd,
                .hurd,
                .haiku,
                .windows,
                => return .gnu,
                .uefi => return .msvc,
                .linux,
                .wasi,
                .emscripten,
                => return .musl,
                .opencl, // TODO: SPIR-V ABIs with Linkage capability
                .glsl450,
                .vulkan,
                .plan9, // TODO specify abi
                .macos,
                .ios,
                .tvos,
                .watchos,
                .driverkit,
                .shadermodel,
                => return .none,
            }
        }

        pub fn isGnu(abi: Abi) bool {
            return switch (abi) {
                .gnu, .gnuabin32, .gnuabi64, .gnueabi, .gnueabihf, .gnux32 => true,
                else => false,
            };
        }

        pub fn isMusl(abi: Abi) bool {
            return switch (abi) {
                .musl, .musleabi, .musleabihf => true,
                else => false,
            };
        }

        pub fn floatAbi(abi: Abi) FloatAbi {
            return switch (abi) {
                .gnueabihf,
                .eabihf,
                .musleabihf,
                => .hard,
                else => .soft,
            };
        }
    };

    pub const ObjectFormat = enum {
        /// Common Object File Format (Windows)
        coff,
        /// DirectX Container
        dxcontainer,
        /// Executable and Linking Format
        elf,
        /// macOS relocatables
        macho,
        /// Standard, Portable Intermediate Representation V
        spirv,
        /// WebAssembly
        wasm,
        /// C source code
        c,
        /// Intel IHEX
        hex,
        /// Machine code with no metadata.
        raw,
        /// Plan 9 from Bell Labs
        plan9,
        /// Nvidia PTX format
        nvptx,

        pub fn fileExt(of: ObjectFormat, cpu_arch: Cpu.Arch) [:0]const u8 {
            return switch (of) {
                .coff => ".obj",
                .elf, .macho, .wasm => ".o",
                .c => ".c",
                .spirv => ".spv",
                .hex => ".ihex",
                .raw => ".bin",
                .plan9 => plan9Ext(cpu_arch),
                .nvptx => ".ptx",
                .dxcontainer => @panic("TODO what's the extension for these?"),
            };
        }

        pub fn default(os_tag: Os.Tag, cpu_arch: Cpu.Arch) ObjectFormat {
            return switch (os_tag) {
                .windows, .uefi => .coff,
                .ios, .macos, .watchos, .tvos => .macho,
                .plan9 => .plan9,
                else => return switch (cpu_arch) {
                    .wasm32, .wasm64 => .wasm,
                    .spirv32, .spirv64 => .spirv,
                    .nvptx, .nvptx64 => .nvptx,
                    else => .elf,
                },
            };
        }
    };

    pub const SubSystem = enum {
        Console,
        Windows,
        Posix,
        Native,
        EfiApplication,
        EfiBootServiceDriver,
        EfiRom,
        EfiRuntimeDriver,
    };

    pub const Cpu = struct {
        /// Architecture
        arch: Arch,

        /// The CPU model to target. It has a set of features
        /// which are overridden with the `features` field.
        model: *const Model,

        /// An explicit list of the entire CPU feature set. It may differ from the specific CPU model's features.
        features: Feature.Set,

        pub const Feature = struct {
            /// The bit index into `Set`. Has a default value of `undefined` because the canonical
            /// structures are populated via comptime logic.
            index: Set.Index = undefined,

            /// Has a default value of `undefined` because the canonical
            /// structures are populated via comptime logic.
            name: []const u8 = undefined,

            /// If this corresponds to an LLVM-recognized feature, this will be populated;
            /// otherwise null.
            llvm_name: ?[:0]const u8,

            /// Human-friendly UTF-8 text.
            description: []const u8,

            /// Sparse `Set` of features this depends on.
            dependencies: Set,

            /// A bit set of all the features.
            pub const Set = struct {
                ints: [usize_count]usize,

                pub const needed_bit_count = 288;
                pub const byte_count = (needed_bit_count + 7) / 8;
                pub const usize_count = (byte_count + (@sizeOf(usize) - 1)) / @sizeOf(usize);
                pub const Index = std.math.Log2Int(std.meta.Int(.unsigned, usize_count * @bitSizeOf(usize)));
                pub const ShiftInt = std.math.Log2Int(usize);

                pub const empty = Set{ .ints = [1]usize{0} ** usize_count };
                pub fn empty_workaround() Set {
                    return Set{ .ints = [1]usize{0} ** usize_count };
                }

                pub fn isEmpty(set: Set) bool {
                    return for (set.ints) |x| {
                        if (x != 0) break false;
                    } else true;
                }

                pub fn isEnabled(set: Set, arch_feature_index: Index) bool {
                    const usize_index = arch_feature_index / @bitSizeOf(usize);
                    const bit_index = @intCast(ShiftInt, arch_feature_index % @bitSizeOf(usize));
                    return (set.ints[usize_index] & (@as(usize, 1) << bit_index)) != 0;
                }

                /// Adds the specified feature but not its dependencies.
                pub fn addFeature(set: *Set, arch_feature_index: Index) void {
                    const usize_index = arch_feature_index / @bitSizeOf(usize);
                    const bit_index = @intCast(ShiftInt, arch_feature_index % @bitSizeOf(usize));
                    set.ints[usize_index] |= @as(usize, 1) << bit_index;
                }

                /// Adds the specified feature set but not its dependencies.
                pub fn addFeatureSet(set: *Set, other_set: Set) void {
                    set.ints = @as(@Vector(usize_count, usize), set.ints) | @as(@Vector(usize_count, usize), other_set.ints);
                }

                /// Removes the specified feature but not its dependents.
                pub fn removeFeature(set: *Set, arch_feature_index: Index) void {
                    const usize_index = arch_feature_index / @bitSizeOf(usize);
                    const bit_index = @intCast(ShiftInt, arch_feature_index % @bitSizeOf(usize));
                    set.ints[usize_index] &= ~(@as(usize, 1) << bit_index);
                }

                /// Removes the specified feature but not its dependents.
                pub fn removeFeatureSet(set: *Set, other_set: Set) void {
                    set.ints = @as(@Vector(usize_count, usize), set.ints) & ~@as(@Vector(usize_count, usize), other_set.ints);
                }

                pub fn populateDependencies(set: *Set, all_features_list: []const Cpu.Feature) void {
                    @setEvalBranchQuota(1000000);

                    var old = set.ints;
                    while (true) {
                        for (all_features_list) |feature, index_usize| {
                            const index = @intCast(Index, index_usize);
                            if (set.isEnabled(index)) {
                                set.addFeatureSet(feature.dependencies);
                            }
                        }
                        const nothing_changed = mem.eql(usize, &old, &set.ints);
                        if (nothing_changed) return;
                        old = set.ints;
                    }
                }

                pub fn asBytes(set: *const Set) *const [byte_count]u8 {
                    return @ptrCast(*const [byte_count]u8, &set.ints);
                }

                pub fn eql(set: Set, other_set: Set) bool {
                    return mem.eql(usize, &set.ints, &other_set.ints);
                }

                pub fn isSuperSetOf(set: Set, other_set: Set) bool {
                    const V = @Vector(usize_count, usize);
                    const set_v: V = set.ints;
                    const other_v: V = other_set.ints;
                    return @reduce(.And, (set_v & other_v) == other_v);
                }
            };

            pub fn feature_set_fns(comptime F: type) type {
                return struct {
                    /// Populates only the feature bits specified.
                    pub fn featureSet(features: []const F) Set {
                        var x = Set.empty_workaround(); // TODO remove empty_workaround
                        for (features) |feature| {
                            x.addFeature(@enumToInt(feature));
                        }
                        return x;
                    }

                    /// Returns true if the specified feature is enabled.
                    pub fn featureSetHas(set: Set, feature: F) bool {
                        return set.isEnabled(@enumToInt(feature));
                    }

                    /// Returns true if any specified feature is enabled.
                    pub fn featureSetHasAny(set: Set, features: anytype) bool {
                        comptime std.debug.assert(std.meta.trait.isIndexable(@TypeOf(features)));
                        inline for (features) |feature| {
                            if (set.isEnabled(@enumToInt(@as(F, feature)))) return true;
                        }
                        return false;
                    }

                    /// Returns true if every specified feature is enabled.
                    pub fn featureSetHasAll(set: Set, features: anytype) bool {
                        comptime std.debug.assert(std.meta.trait.isIndexable(@TypeOf(features)));
                        inline for (features) |feature| {
                            if (!set.isEnabled(@enumToInt(@as(F, feature)))) return false;
                        }
                        return true;
                    }
                };
            }
        };

        pub const Arch = enum {
            arm,
            armeb,
            aarch64,
            aarch64_be,
            aarch64_32,
            arc,
            avr,
            bpfel,
            bpfeb,
            csky,
            dxil,
            hexagon,
            loongarch32,
            loongarch64,
            m68k,
            mips,
            mipsel,
            mips64,
            mips64el,
            msp430,
            powerpc,
            powerpcle,
            powerpc64,
            powerpc64le,
            r600,
            amdgcn,
            riscv32,
            riscv64,
            sparc,
            sparc64,
            sparcel,
            s390x,
            tce,
            tcele,
            thumb,
            thumbeb,
            i386,
            x86_64,
            xcore,
            nvptx,
            nvptx64,
            le32,
            le64,
            amdil,
            amdil64,
            hsail,
            hsail64,
            spir,
            spir64,
            spirv32,
            spirv64,
            kalimba,
            shave,
            lanai,
            wasm32,
            wasm64,
            renderscript32,
            renderscript64,
            ve,
            // Stage1 currently assumes that architectures above this comment
            // map one-to-one with the ZigLLVM_ArchType enum.
            spu_2,

            pub fn isX86(arch: Arch) bool {
                return switch (arch) {
                    .i386, .x86_64 => true,
                    else => false,
                };
            }

            pub fn isARM(arch: Arch) bool {
                return switch (arch) {
                    .arm, .armeb => true,
                    else => false,
                };
            }

            pub fn isAARCH64(arch: Arch) bool {
                return switch (arch) {
                    .aarch64, .aarch64_be, .aarch64_32 => true,
                    else => false,
                };
            }

            pub fn isThumb(arch: Arch) bool {
                return switch (arch) {
                    .thumb, .thumbeb => true,
                    else => false,
                };
            }

            pub fn isWasm(arch: Arch) bool {
                return switch (arch) {
                    .wasm32, .wasm64 => true,
                    else => false,
                };
            }

            pub fn isRISCV(arch: Arch) bool {
                return switch (arch) {
                    .riscv32, .riscv64 => true,
                    else => false,
                };
            }

            pub fn isMIPS(arch: Arch) bool {
                return switch (arch) {
                    .mips, .mipsel, .mips64, .mips64el => true,
                    else => false,
                };
            }

            pub fn isPPC(arch: Arch) bool {
                return switch (arch) {
                    .powerpc, .powerpcle => true,
                    else => false,
                };
            }

            pub fn isPPC64(arch: Arch) bool {
                return switch (arch) {
                    .powerpc64, .powerpc64le => true,
                    else => false,
                };
            }

            pub fn isSPARC(arch: Arch) bool {
                return switch (arch) {
                    .sparc, .sparcel, .sparc64 => true,
                    else => false,
                };
            }

            pub fn isSPIRV(arch: Arch) bool {
                return switch (arch) {
                    .spirv32, .spirv64 => true,
                    else => false,
                };
            }

            pub fn isBpf(arch: Arch) bool {
                return switch (arch) {
                    .bpfel, .bpfeb => true,
                    else => false,
                };
            }

            pub fn isNvptx(arch: Arch) bool {
                return switch (arch) {
                    .nvptx, .nvptx64 => true,
                    else => false,
                };
            }

            pub fn parseCpuModel(arch: Arch, cpu_name: []const u8) !*const Cpu.Model {
                for (arch.allCpuModels()) |cpu| {
                    if (mem.eql(u8, cpu_name, cpu.name)) {
                        return cpu;
                    }
                }
                return error.UnknownCpuModel;
            }

            pub fn toElfMachine(arch: Arch) std.elf.EM {
                return switch (arch) {
                    .avr => .AVR,
                    .msp430 => .MSP430,
                    .arc => .ARC,
                    .arm => .ARM,
                    .armeb => .ARM,
                    .hexagon => .HEXAGON,
                    .dxil => .NONE,
                    .m68k => .@"68K",
                    .le32 => .NONE,
                    .mips => .MIPS,
                    .mipsel => .MIPS_RS3_LE,
                    .powerpc, .powerpcle => .PPC,
                    .r600 => .NONE,
                    .riscv32 => .RISCV,
                    .sparc => .SPARC,
                    .sparcel => .SPARC,
                    .tce => .NONE,
                    .tcele => .NONE,
                    .thumb => .ARM,
                    .thumbeb => .ARM,
                    .i386 => .@"386",
                    .xcore => .XCORE,
                    .nvptx => .NONE,
                    .amdil => .NONE,
                    .hsail => .NONE,
                    .spir => .NONE,
                    .kalimba => .CSR_KALIMBA,
                    .shave => .NONE,
                    .lanai => .LANAI,
                    .wasm32 => .NONE,
                    .renderscript32 => .NONE,
                    .aarch64_32 => .AARCH64,
                    .aarch64 => .AARCH64,
                    .aarch64_be => .AARCH64,
                    .mips64 => .MIPS,
                    .mips64el => .MIPS_RS3_LE,
                    .powerpc64 => .PPC64,
                    .powerpc64le => .PPC64,
                    .riscv64 => .RISCV,
                    .x86_64 => .X86_64,
                    .nvptx64 => .NONE,
                    .le64 => .NONE,
                    .amdil64 => .NONE,
                    .hsail64 => .NONE,
                    .spir64 => .NONE,
                    .wasm64 => .NONE,
                    .renderscript64 => .NONE,
                    .amdgcn => .NONE,
                    .bpfel => .BPF,
                    .bpfeb => .BPF,
                    .csky => .CSKY,
                    .sparc64 => .SPARCV9,
                    .s390x => .S390,
                    .ve => .NONE,
                    .spu_2 => .SPU_2,
                    .spirv32 => .NONE,
                    .spirv64 => .NONE,
                    .loongarch32 => .NONE,
                    .loongarch64 => .NONE,
                };
            }

            pub fn toCoffMachine(arch: Arch) std.coff.MachineType {
                return switch (arch) {
                    .avr => .Unknown,
                    .msp430 => .Unknown,
                    .arc => .Unknown,
                    .arm => .ARM,
                    .armeb => .Unknown,
                    .dxil => .Unknown,
                    .hexagon => .Unknown,
                    .m68k => .Unknown,
                    .le32 => .Unknown,
                    .mips => .Unknown,
                    .mipsel => .Unknown,
                    .powerpc, .powerpcle => .POWERPC,
                    .r600 => .Unknown,
                    .riscv32 => .RISCV32,
                    .sparc => .Unknown,
                    .sparcel => .Unknown,
                    .tce => .Unknown,
                    .tcele => .Unknown,
                    .thumb => .Thumb,
                    .thumbeb => .Thumb,
                    .i386 => .I386,
                    .xcore => .Unknown,
                    .nvptx => .Unknown,
                    .amdil => .Unknown,
                    .hsail => .Unknown,
                    .spir => .Unknown,
                    .kalimba => .Unknown,
                    .shave => .Unknown,
                    .lanai => .Unknown,
                    .wasm32 => .Unknown,
                    .renderscript32 => .Unknown,
                    .aarch64_32 => .ARM64,
                    .aarch64 => .ARM64,
                    .aarch64_be => .Unknown,
                    .mips64 => .Unknown,
                    .mips64el => .Unknown,
                    .powerpc64 => .Unknown,
                    .powerpc64le => .Unknown,
                    .riscv64 => .RISCV64,
                    .x86_64 => .X64,
                    .nvptx64 => .Unknown,
                    .le64 => .Unknown,
                    .amdil64 => .Unknown,
                    .hsail64 => .Unknown,
                    .spir64 => .Unknown,
                    .wasm64 => .Unknown,
                    .renderscript64 => .Unknown,
                    .amdgcn => .Unknown,
                    .bpfel => .Unknown,
                    .bpfeb => .Unknown,
                    .csky => .Unknown,
                    .sparc64 => .Unknown,
                    .s390x => .Unknown,
                    .ve => .Unknown,
                    .spu_2 => .Unknown,
                    .spirv32 => .Unknown,
                    .spirv64 => .Unknown,
                    .loongarch32 => .Unknown,
                    .loongarch64 => .Unknown,
                };
            }

            pub fn endian(arch: Arch) std.builtin.Endian {
                return switch (arch) {
                    .avr,
                    .arm,
                    .aarch64_32,
                    .aarch64,
                    .amdgcn,
                    .amdil,
                    .amdil64,
                    .bpfel,
                    .csky,
                    .hexagon,
                    .hsail,
                    .hsail64,
                    .kalimba,
                    .le32,
                    .le64,
                    .mipsel,
                    .mips64el,
                    .msp430,
                    .nvptx,
                    .nvptx64,
                    .sparcel,
                    .tcele,
                    .powerpcle,
                    .powerpc64le,
                    .r600,
                    .riscv32,
                    .riscv64,
                    .i386,
                    .x86_64,
                    .wasm32,
                    .wasm64,
                    .xcore,
                    .thumb,
                    .spir,
                    .spir64,
                    .renderscript32,
                    .renderscript64,
                    .shave,
                    .ve,
                    .spu_2,
                    // GPU bitness is opaque. For now, assume little endian.
                    .spirv32,
                    .spirv64,
                    .dxil,
                    .loongarch32,
                    .loongarch64,
                    => .Little,

                    .arc,
                    .armeb,
                    .aarch64_be,
                    .bpfeb,
                    .m68k,
                    .mips,
                    .mips64,
                    .powerpc,
                    .powerpc64,
                    .thumbeb,
                    .sparc,
                    .sparc64,
                    .tce,
                    .lanai,
                    .s390x,
                    => .Big,
                };
            }

            /// Returns whether this architecture supports the address space
            pub fn supportsAddressSpace(arch: Arch, address_space: std.builtin.AddressSpace) bool {
                const is_nvptx = arch == .nvptx or arch == .nvptx64;
                return switch (address_space) {
                    .generic => true,
                    .fs, .gs, .ss => arch == .x86_64 or arch == .i386,
                    .global, .constant, .local, .shared => arch == .amdgcn or is_nvptx,
                    .param => is_nvptx,
                };
            }

            pub fn ptrBitWidth(arch: Arch) u16 {
                switch (arch) {
                    .avr,
                    .msp430,
                    .spu_2,
                    => return 16,

                    .arc,
                    .arm,
                    .armeb,
                    .csky,
                    .hexagon,
                    .m68k,
                    .le32,
                    .mips,
                    .mipsel,
                    .powerpc,
                    .powerpcle,
                    .r600,
                    .riscv32,
                    .sparc,
                    .sparcel,
                    .tce,
                    .tcele,
                    .thumb,
                    .thumbeb,
                    .i386,
                    .xcore,
                    .nvptx,
                    .amdil,
                    .hsail,
                    .spir,
                    .kalimba,
                    .shave,
                    .lanai,
                    .wasm32,
                    .renderscript32,
                    .aarch64_32,
                    .spirv32,
                    .loongarch32,
                    .dxil,
                    => return 32,

                    .aarch64,
                    .aarch64_be,
                    .mips64,
                    .mips64el,
                    .powerpc64,
                    .powerpc64le,
                    .riscv64,
                    .x86_64,
                    .nvptx64,
                    .le64,
                    .amdil64,
                    .hsail64,
                    .spir64,
                    .wasm64,
                    .renderscript64,
                    .amdgcn,
                    .bpfel,
                    .bpfeb,
                    .sparc64,
                    .s390x,
                    .ve,
                    .spirv64,
                    .loongarch64,
                    => return 64,
                }
            }

            /// Returns a name that matches the lib/std/target/* source file name.
            pub fn genericName(arch: Arch) []const u8 {
                return switch (arch) {
                    .arm, .armeb, .thumb, .thumbeb => "arm",
                    .aarch64, .aarch64_be, .aarch64_32 => "aarch64",
                    .bpfel, .bpfeb => "bpf",
                    .mips, .mipsel, .mips64, .mips64el => "mips",
                    .powerpc, .powerpcle, .powerpc64, .powerpc64le => "powerpc",
                    .amdgcn => "amdgpu",
                    .riscv32, .riscv64 => "riscv",
                    .sparc, .sparc64, .sparcel => "sparc",
                    .s390x => "s390x",
                    .i386, .x86_64 => "x86",
                    .nvptx, .nvptx64 => "nvptx",
                    .wasm32, .wasm64 => "wasm",
                    .spirv32, .spirv64 => "spir-v",
                    else => @tagName(arch),
                };
            }

            /// All CPU features Zig is aware of, sorted lexicographically by name.
            pub fn allFeaturesList(arch: Arch) []const Cpu.Feature {
                return switch (arch) {
                    .arm, .armeb, .thumb, .thumbeb => &arm.all_features,
                    .aarch64, .aarch64_be, .aarch64_32 => &aarch64.all_features,
                    .avr => &avr.all_features,
                    .bpfel, .bpfeb => &bpf.all_features,
                    .hexagon => &hexagon.all_features,
                    .mips, .mipsel, .mips64, .mips64el => &mips.all_features,
                    .msp430 => &msp430.all_features,
                    .powerpc, .powerpcle, .powerpc64, .powerpc64le => &powerpc.all_features,
                    .amdgcn => &amdgpu.all_features,
                    .riscv32, .riscv64 => &riscv.all_features,
                    .sparc, .sparc64, .sparcel => &sparc.all_features,
                    .spirv32, .spirv64 => &spirv.all_features,
                    .s390x => &s390x.all_features,
                    .i386, .x86_64 => &x86.all_features,
                    .nvptx, .nvptx64 => &nvptx.all_features,
                    .ve => &ve.all_features,
                    .wasm32, .wasm64 => &wasm.all_features,

                    else => &[0]Cpu.Feature{},
                };
            }

            /// All processors Zig is aware of, sorted lexicographically by name.
            pub fn allCpuModels(arch: Arch) []const *const Cpu.Model {
                return switch (arch) {
                    .arm, .armeb, .thumb, .thumbeb => comptime allCpusFromDecls(arm.cpu),
                    .aarch64, .aarch64_be, .aarch64_32 => comptime allCpusFromDecls(aarch64.cpu),
                    .avr => comptime allCpusFromDecls(avr.cpu),
                    .bpfel, .bpfeb => comptime allCpusFromDecls(bpf.cpu),
                    .hexagon => comptime allCpusFromDecls(hexagon.cpu),
                    .mips, .mipsel, .mips64, .mips64el => comptime allCpusFromDecls(mips.cpu),
                    .msp430 => comptime allCpusFromDecls(msp430.cpu),
                    .powerpc, .powerpcle, .powerpc64, .powerpc64le => comptime allCpusFromDecls(powerpc.cpu),
                    .amdgcn => comptime allCpusFromDecls(amdgpu.cpu),
                    .riscv32, .riscv64 => comptime allCpusFromDecls(riscv.cpu),
                    .sparc, .sparc64, .sparcel => comptime allCpusFromDecls(sparc.cpu),
                    .s390x => comptime allCpusFromDecls(s390x.cpu),
                    .i386, .x86_64 => comptime allCpusFromDecls(x86.cpu),
                    .nvptx, .nvptx64 => comptime allCpusFromDecls(nvptx.cpu),
                    .ve => comptime allCpusFromDecls(ve.cpu),
                    .wasm32, .wasm64 => comptime allCpusFromDecls(wasm.cpu),

                    else => &[0]*const Model{},
                };
            }

            fn allCpusFromDecls(comptime cpus: type) []const *const Cpu.Model {
                const decls = @typeInfo(cpus).Struct.decls;
                var array: [decls.len]*const Cpu.Model = undefined;
                for (decls) |decl, i| {
                    array[i] = &@field(cpus, decl.name);
                }
                return &array;
            }
        };

        pub const Model = struct {
            name: []const u8,
            llvm_name: ?[:0]const u8,
            features: Feature.Set,

            pub fn toCpu(model: *const Model, arch: Arch) Cpu {
                var features = model.features;
                features.populateDependencies(arch.allFeaturesList());
                return .{
                    .arch = arch,
                    .model = model,
                    .features = features,
                };
            }

            pub fn generic(arch: Arch) *const Model {
                const S = struct {
                    const generic_model = Model{
                        .name = "generic",
                        .llvm_name = null,
                        .features = Cpu.Feature.Set.empty,
                    };
                };
                return switch (arch) {
                    .arm, .armeb, .thumb, .thumbeb => &arm.cpu.generic,
                    .aarch64, .aarch64_be, .aarch64_32 => &aarch64.cpu.generic,
                    .avr => &avr.cpu.avr2,
                    .bpfel, .bpfeb => &bpf.cpu.generic,
                    .hexagon => &hexagon.cpu.generic,
                    .m68k => &m68k.cpu.generic,
                    .mips, .mipsel => &mips.cpu.mips32,
                    .mips64, .mips64el => &mips.cpu.mips64,
                    .msp430 => &msp430.cpu.generic,
                    .powerpc => &powerpc.cpu.ppc,
                    .powerpcle => &powerpc.cpu.ppc,
                    .powerpc64 => &powerpc.cpu.ppc64,
                    .powerpc64le => &powerpc.cpu.ppc64le,
                    .amdgcn => &amdgpu.cpu.generic,
                    .riscv32 => &riscv.cpu.generic_rv32,
                    .riscv64 => &riscv.cpu.generic_rv64,
                    .sparc, .sparcel => &sparc.cpu.generic,
                    .sparc64 => &sparc.cpu.v9, // 64-bit SPARC needs v9 as the baseline
                    .s390x => &s390x.cpu.generic,
                    .i386 => &x86.cpu.i386,
                    .x86_64 => &x86.cpu.x86_64,
                    .nvptx, .nvptx64 => &nvptx.cpu.sm_20,
                    .ve => &ve.cpu.generic,
                    .wasm32, .wasm64 => &wasm.cpu.generic,

                    else => &S.generic_model,
                };
            }

            pub fn baseline(arch: Arch) *const Model {
                return switch (arch) {
                    .arm, .armeb, .thumb, .thumbeb => &arm.cpu.baseline,
                    .riscv32 => &riscv.cpu.baseline_rv32,
                    .riscv64 => &riscv.cpu.baseline_rv64,
                    .i386 => &x86.cpu.pentium4,
                    .nvptx, .nvptx64 => &nvptx.cpu.sm_20,
                    .sparc, .sparcel => &sparc.cpu.v8,

                    else => generic(arch),
                };
            }
        };

        /// The "default" set of CPU features for cross-compiling. A conservative set
        /// of features that is expected to be supported on most available hardware.
        pub fn baseline(arch: Arch) Cpu {
            return Model.baseline(arch).toCpu(arch);
        }
    };

    pub const stack_align = 16;

    pub fn zigTriple(self: Target, allocator: mem.Allocator) ![]u8 {
        return std.zig.CrossTarget.fromTarget(self).zigTriple(allocator);
    }

    pub fn linuxTripleSimple(allocator: mem.Allocator, cpu_arch: Cpu.Arch, os_tag: Os.Tag, abi: Abi) ![]u8 {
        return std.fmt.allocPrint(allocator, "{s}-{s}-{s}", .{ @tagName(cpu_arch), @tagName(os_tag), @tagName(abi) });
    }

    pub fn linuxTriple(self: Target, allocator: mem.Allocator) ![]u8 {
        return linuxTripleSimple(allocator, self.cpu.arch, self.os.tag, self.abi);
    }

    pub fn exeFileExtSimple(cpu_arch: Cpu.Arch, os_tag: Os.Tag) [:0]const u8 {
        return switch (os_tag) {
            .windows => ".exe",
            .uefi => ".efi",
            .plan9 => plan9Ext(cpu_arch),
            else => switch (cpu_arch) {
                .wasm32, .wasm64 => ".wasm",
                else => "",
            },
        };
    }

    pub fn exeFileExt(self: Target) [:0]const u8 {
        return exeFileExtSimple(self.cpu.arch, self.os.tag);
    }

    pub fn staticLibSuffix_os_abi(os_tag: Os.Tag, abi: Abi) [:0]const u8 {
        if (abi == .msvc) {
            return ".lib";
        }
        switch (os_tag) {
            .windows, .uefi => return ".lib",
            else => return ".a",
        }
    }

    pub fn staticLibSuffix(self: Target) [:0]const u8 {
        return staticLibSuffix_os_abi(self.os.tag, self.abi);
    }

    pub fn dynamicLibSuffix(self: Target) [:0]const u8 {
        return self.os.tag.dynamicLibSuffix();
    }

    pub fn libPrefix_os_abi(os_tag: Os.Tag, abi: Abi) [:0]const u8 {
        if (abi == .msvc) {
            return "";
        }
        switch (os_tag) {
            .windows, .uefi => return "",
            else => return "lib",
        }
    }

    pub fn libPrefix(self: Target) [:0]const u8 {
        return libPrefix_os_abi(self.os.tag, self.abi);
    }

    pub fn isMinGW(self: Target) bool {
        return self.os.tag == .windows and self.isGnu();
    }

    pub fn isGnu(self: Target) bool {
        return self.abi.isGnu();
    }

    pub fn isMusl(self: Target) bool {
        return self.abi.isMusl();
    }

    pub fn isAndroid(self: Target) bool {
        return self.abi == .android;
    }

    pub fn isWasm(self: Target) bool {
        return self.cpu.arch.isWasm();
    }

    pub fn isDarwin(self: Target) bool {
        return self.os.tag.isDarwin();
    }

    pub fn isBSD(self: Target) bool {
        return self.os.tag.isBSD();
    }

    pub fn isBpfFreestanding(self: Target) bool {
        return self.cpu.arch.isBpf() and self.os.tag == .freestanding;
    }

    pub fn isGnuLibC_os_tag_abi(os_tag: Os.Tag, abi: Abi) bool {
        return os_tag == .linux and abi.isGnu();
    }

    pub fn isGnuLibC(self: Target) bool {
        return isGnuLibC_os_tag_abi(self.os.tag, self.abi);
    }

    pub fn supportsNewStackCall(self: Target) bool {
        return !self.cpu.arch.isWasm();
    }

    pub const FloatAbi = enum {
        hard,
        soft,
        soft_fp,
    };

    pub fn getFloatAbi(self: Target) FloatAbi {
        return self.abi.floatAbi();
    }

    pub fn hasDynamicLinker(self: Target) bool {
        if (self.cpu.arch.isWasm()) {
            return false;
        }
        switch (self.os.tag) {
            .freestanding,
            .ios,
            .tvos,
            .watchos,
            .macos,
            .uefi,
            .windows,
            .emscripten,
            .opencl,
            .glsl450,
            .vulkan,
            .plan9,
            .other,
            => return false,
            else => return true,
        }
    }

    pub const DynamicLinker = struct {
        /// Contains the memory used to store the dynamic linker path. This field should
        /// not be used directly. See `get` and `set`. This field exists so that this API requires no allocator.
        buffer: [255]u8 = undefined,

        /// Used to construct the dynamic linker path. This field should not be used
        /// directly. See `get` and `set`.
        max_byte: ?u8 = null,

        /// Asserts that the length is less than or equal to 255 bytes.
        pub fn init(dl_or_null: ?[]const u8) DynamicLinker {
            var result: DynamicLinker = undefined;
            result.set(dl_or_null);
            return result;
        }

        /// The returned memory has the same lifetime as the `DynamicLinker`.
        pub fn get(self: *const DynamicLinker) ?[]const u8 {
            const m: usize = self.max_byte orelse return null;
            return self.buffer[0 .. m + 1];
        }

        /// Asserts that the length is less than or equal to 255 bytes.
        pub fn set(self: *DynamicLinker, dl_or_null: ?[]const u8) void {
            if (dl_or_null) |dl| {
                mem.copy(u8, &self.buffer, dl);
                self.max_byte = @intCast(u8, dl.len - 1);
            } else {
                self.max_byte = null;
            }
        }
    };

    pub fn standardDynamicLinkerPath(self: Target) DynamicLinker {
        var result: DynamicLinker = .{};
        const S = struct {
            fn print(r: *DynamicLinker, comptime fmt: []const u8, args: anytype) DynamicLinker {
                r.max_byte = @intCast(u8, (std.fmt.bufPrint(&r.buffer, fmt, args) catch unreachable).len - 1);
                return r.*;
            }
            fn copy(r: *DynamicLinker, s: []const u8) DynamicLinker {
                mem.copy(u8, &r.buffer, s);
                r.max_byte = @intCast(u8, s.len - 1);
                return r.*;
            }
        };
        const print = S.print;
        const copy = S.copy;

        if (self.abi == .android) {
            const suffix = if (self.cpu.arch.ptrBitWidth() == 64) "64" else "";
            return print(&result, "/system/bin/linker{s}", .{suffix});
        }

        if (self.abi.isMusl()) {
            const is_arm = switch (self.cpu.arch) {
                .arm, .armeb, .thumb, .thumbeb => true,
                else => false,
            };
            const arch_part = switch (self.cpu.arch) {
                .arm, .thumb => "arm",
                .armeb, .thumbeb => "armeb",
                else => |arch| @tagName(arch),
            };
            const arch_suffix = if (is_arm and self.abi.floatAbi() == .hard) "hf" else "";
            return print(&result, "/lib/ld-musl-{s}{s}.so.1", .{ arch_part, arch_suffix });
        }

        switch (self.os.tag) {
            .freebsd => return copy(&result, "/libexec/ld-elf.so.1"),
            .netbsd => return copy(&result, "/libexec/ld.elf_so"),
            .openbsd => return copy(&result, "/usr/libexec/ld.so"),
            .dragonfly => return copy(&result, "/libexec/ld-elf.so.2"),
            .solaris => return copy(&result, "/lib/64/ld.so.1"),
            .linux => switch (self.cpu.arch) {
                .i386,
                .sparc,
                .sparcel,
                => return copy(&result, "/lib/ld-linux.so.2"),

                .aarch64 => return copy(&result, "/lib/ld-linux-aarch64.so.1"),
                .aarch64_be => return copy(&result, "/lib/ld-linux-aarch64_be.so.1"),
                .aarch64_32 => return copy(&result, "/lib/ld-linux-aarch64_32.so.1"),

                .arm,
                .armeb,
                .thumb,
                .thumbeb,
                => return copy(&result, switch (self.abi.floatAbi()) {
                    .hard => "/lib/ld-linux-armhf.so.3",
                    else => "/lib/ld-linux.so.3",
                }),

                .mips,
                .mipsel,
                .mips64,
                .mips64el,
                => {
                    const lib_suffix = switch (self.abi) {
                        .gnuabin32, .gnux32 => "32",
                        .gnuabi64 => "64",
                        else => "",
                    };
                    const is_nan_2008 = mips.featureSetHas(self.cpu.features, .nan2008);
                    const loader = if (is_nan_2008) "ld-linux-mipsn8.so.1" else "ld.so.1";
                    return print(&result, "/lib{s}/{s}", .{ lib_suffix, loader });
                },

                .powerpc, .powerpcle => return copy(&result, "/lib/ld.so.1"),
                .powerpc64, .powerpc64le => return copy(&result, "/lib64/ld64.so.2"),
                .s390x => return copy(&result, "/lib64/ld64.so.1"),
                .sparc64 => return copy(&result, "/lib64/ld-linux.so.2"),
                .x86_64 => return copy(&result, switch (self.abi) {
                    .gnux32 => "/libx32/ld-linux-x32.so.2",
                    else => "/lib64/ld-linux-x86-64.so.2",
                }),

                .riscv32 => return copy(&result, "/lib/ld-linux-riscv32-ilp32.so.1"),
                .riscv64 => return copy(&result, "/lib/ld-linux-riscv64-lp64.so.1"),

                // Architectures in this list have been verified as not having a standard
                // dynamic linker path.
                .wasm32,
                .wasm64,
                .bpfel,
                .bpfeb,
                .nvptx,
                .nvptx64,
                .spu_2,
                .avr,
                .spirv32,
                .spirv64,
                => return result,

                // TODO go over each item in this list and either move it to the above list, or
                // implement the standard dynamic linker path code for it.
                .arc,
                .csky,
                .hexagon,
                .m68k,
                .msp430,
                .r600,
                .amdgcn,
                .tce,
                .tcele,
                .xcore,
                .le32,
                .le64,
                .amdil,
                .amdil64,
                .hsail,
                .hsail64,
                .spir,
                .spir64,
                .kalimba,
                .shave,
                .lanai,
                .renderscript32,
                .renderscript64,
                .ve,
                .dxil,
                .loongarch32,
                .loongarch64,
                => return result,
            },

            .ios,
            .tvos,
            .watchos,
            .macos,
            => return copy(&result, "/usr/lib/dyld"),

            // Operating systems in this list have been verified as not having a standard
            // dynamic linker path.
            .freestanding,
            .uefi,
            .windows,
            .emscripten,
            .wasi,
            .opencl,
            .glsl450,
            .vulkan,
            .other,
            .plan9,
            => return result,

            // TODO revisit when multi-arch for Haiku is available
            .haiku => return copy(&result, "/system/runtime_loader"),

            // TODO go over each item in this list and either move it to the above list, or
            // implement the standard dynamic linker path code for it.
            .ananas,
            .cloudabi,
            .fuchsia,
            .kfreebsd,
            .lv2,
            .zos,
            .minix,
            .rtems,
            .nacl,
            .aix,
            .cuda,
            .nvcl,
            .amdhsa,
            .ps4,
            .ps5,
            .elfiamcu,
            .mesa3d,
            .contiki,
            .amdpal,
            .hermit,
            .hurd,
            .driverkit,
            .shadermodel,
            => return result,
        }
    }

    /// 0c spim    little-endian MIPS 3000 family
    /// 1c 68000   Motorola MC68000
    /// 2c 68020   Motorola MC68020
    /// 5c arm     little-endian ARM
    /// 6c amd64   AMD64 and compatibles (e.g., Intel EM64T)
    /// 7c arm64   ARM64 (ARMv8)
    /// 8c 386     Intel i386, i486, Pentium, etc.
    /// kc sparc   Sun SPARC
    /// qc power   Power PC
    /// vc mips    big-endian MIPS 3000 family
    pub fn plan9Ext(cpu_arch: Cpu.Arch) [:0]const u8 {
        return switch (cpu_arch) {
            .arm => ".5",
            .x86_64 => ".6",
            .aarch64 => ".7",
            .i386 => ".8",
            .sparc => ".k",
            .powerpc, .powerpcle => ".q",
            .mips, .mipsel => ".v",
            // ISAs without designated characters get 'X' for lack of a better option.
            else => ".X",
        };
    }

    pub inline fn maxIntAlignment(target: Target) u16 {
        return switch (target.cpu.arch) {
            .avr => 1,
            .msp430 => 2,
            .xcore => 4,

            .arm,
            .armeb,
            .thumb,
            .thumbeb,
            .hexagon,
            .mips,
            .mipsel,
            .powerpc,
            .powerpcle,
            .r600,
            .amdgcn,
            .riscv32,
            .sparc,
            .sparcel,
            .s390x,
            .lanai,
            .wasm32,
            .wasm64,
            => 8,

            .i386 => return switch (target.os.tag) {
                .windows, .uefi => 8,
                else => 4,
            },

            // For these, LLVMABIAlignmentOfType(i128) reports 8. Note that 16
            // is a relevant number in three cases:
            // 1. Different machine code instruction when loading into SIMD register.
            // 2. The C ABI wants 16 for extern structs.
            // 3. 16-byte cmpxchg needs 16-byte alignment.
            // Same logic for powerpc64, mips64, sparc64.
            .x86_64,
            .powerpc64,
            .powerpc64le,
            .mips64,
            .mips64el,
            .sparc64,
            => return switch (target.ofmt) {
                .c => 16,
                else => 8,
            },

            // Even LLVMABIAlignmentOfType(i128) agrees on these targets.
            .aarch64,
            .aarch64_be,
            .aarch64_32,
            .riscv64,
            .bpfel,
            .bpfeb,
            .nvptx,
            .nvptx64,
            => 16,

            // Below this comment are unverified but based on the fact that C requires
            // int128_t to be 16 bytes aligned, it's a safe default.
            .spu_2,
            .csky,
            .arc,
            .m68k,
            .tce,
            .tcele,
            .le32,
            .amdil,
            .hsail,
            .spir,
            .kalimba,
            .renderscript32,
            .spirv32,
            .shave,
            .le64,
            .amdil64,
            .hsail64,
            .spir64,
            .renderscript64,
            .ve,
            .spirv64,
            .dxil,
            .loongarch32,
            .loongarch64,
            => 16,
        };
    }
};

test {
    std.testing.refAllDecls(Target.Cpu.Arch);
}
