const std = @import("std");
const mach = @import("deps/mach/build.zig");
const Pkg = std.build.Pkg;

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const options = mach.Options{ .core = .{
        .gpu_dawn_options = .{
            .from_source = b.option(bool, "dawn-from-source", "Build Dawn from source") orelse false,
            .debug = b.option(bool, "dawn-debug", "Use a debug build of Dawn") orelse false,
        },
    }};

    try ensureDependencies(b.allocator);

    const app = try mach.App.init(b, .{
        .name = "torto",
        .src = "src/main.zig",
        .target = target,
        .mode = mode,
        .deps = &.{ Packages.zmath, Packages.zigimg, Packages.assets },
        .res_dirs = null,
        .watch_paths = &.{},
        // .use_freetype = "freetype",
        .use_freetype = null,
        .use_model3d = false,
    });

    try app.link(options);
    app.install();

    const runCmd = try app.run();
    runCmd.dependOn(&app.getInstallStep().?.step);
    const runStep = b.step("run", "Run the app");
    runStep.dependOn(runCmd);

    const runTests = b.step("test", "Run tests");
    const testSrcs = [_][]const u8 {
    };
    for (testSrcs) |src| {
        const tests = b.addTest(src);
        tests.setBuildMode(mode);
        tests.setTarget(target);
        runTests.dependOn(&tests.step);
    }
}

const Packages = struct {
    // Declared here because submodule may not be cloned at the time build.zig runs.
    const zmath = Pkg{
        .name = "zmath",
        .source = .{ .path = "deps/zmath/src/zmath.zig" },
    };
    const zigimg = Pkg{
        .name = "zigimg",
        .source = .{ .path = "deps/zigimg/zigimg.zig" },
    };
    // const model3d = Pkg{
    //     .name = "model3d",
    //     .source = .{ .path = "libs/mach/libs/model3d/src/main.zig" },
    // };
    // const mach_imgui = Pkg{
    //     .name = "mach-imgui",
    //     .source = .{ .path = "libs/imgui/src/main.zig" },
    // };
    const assets = Pkg{
        .name = "assets",
        .source = .{ .path = "assets/assets.zig" },
    };
};

pub fn copyFile(src_path: []const u8, dst_path: []const u8) void {
    std.fs.cwd().makePath(std.fs.path.dirname(dst_path).?) catch unreachable;
    std.fs.cwd().copyFile(src_path, std.fs.cwd(), dst_path, .{}) catch unreachable;
}

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}

fn ensureDependencies(allocator: std.mem.Allocator) !void {
    ensureGit(allocator);
    try ensureSubmodule(allocator, "deps/mach");
    try ensureSubmodule(allocator, "deps/zmath");
    try ensureSubmodule(allocator, "deps/zigimg");
}

fn ensureSubmodule(allocator: std.mem.Allocator, path: []const u8) !void {
    if (std.process.getEnvVarOwned(allocator, "NO_ENSURE_SUBMODULES")) |no_ensure_submodules| {
        defer allocator.free(no_ensure_submodules);
        if (std.mem.eql(u8, no_ensure_submodules, "true")) return;
    } else |_| {}
    var child = std.ChildProcess.init(&.{ "git", "submodule", "update", "--init", path }, allocator);
    child.cwd = sdkPath("/");
    child.stderr = std.io.getStdErr();
    child.stdout = std.io.getStdOut();

    _ = try child.spawnAndWait();
}

fn ensureGit(allocator: std.mem.Allocator) void {
    const result = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{ "git", "--version" },
    }) catch { // e.g. FileNotFound
        std.log.err("mach: error: 'git --version' failed. Is git not installed?", .{});
        std.process.exit(1);
    };
    defer {
        allocator.free(result.stderr);
        allocator.free(result.stdout);
    }
    if (result.term.Exited != 0) {
        std.log.err("mach: error: 'git --version' failed. Is git not installed?", .{});
        std.process.exit(1);
    }
}
