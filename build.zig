const std_build = @import("std").build;
const Builder = std_build.Builder;
const Pkg = std_build.Pkg;

const pkg_nitori = Pkg{
    .name = "nitori",
    .path = "lib/nitori/src/main.zig",
};

const pkg_json = Pkg{
    .name = "json",
    .path = "lib/maru/lib/json/json.zig",
};

const pkg_maru = Pkg{
    .name = "maru",
    .path = "lib/maru/src/main.zig",
    .dependencies = &[_]Pkg{
        pkg_nitori,
        pkg_json,
    },
};

const pkg_kasumi = Pkg{
    .name = "kasumi",
    .path = "lib/kasumi/src/main.zig",
    .dependencies = &[_]Pkg{
        pkg_nitori,
    },
};

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("platformer", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    exe.addPackage(pkg_nitori);
    exe.addPackage(pkg_maru);
    exe.addPackage(pkg_kasumi);

    exe.addIncludeDir("/usr/include");

    exe.addIncludeDir("lib/maru/deps/stb");
    exe.addCSourceFile("lib/maru/deps/stb/stb_image.c", &[_][]const u8{"-std=c99"});

    exe.addLibPath("/usr/lib");
    exe.linkLibC();
    exe.linkSystemLibrary("epoxy");
    exe.linkSystemLibrary("portaudio");
    exe.linkSystemLibrary("glfw3");
    exe.linkSystemLibrary("lua");

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
