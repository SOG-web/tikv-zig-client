const std = @import("std");
const protobuf = @import("protobuf");

fn addCSourcesRecursively(b: *std.Build, comp: *std.Build.Step.Compile, dir_path: []const u8) void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();
    var it = dir.iterate();
    while (it.next() catch return) |entry| {
        switch (entry.kind) {
            .file => {
                if (std.mem.endsWith(u8, entry.name, ".c")) {
                    const child_path = std.fs.path.join(b.allocator, &.{ dir_path, entry.name }) catch continue;
                    defer b.allocator.free(child_path);
                    comp.addCSourceFile(.{ .file = b.path(child_path), .flags = &.{} });
                }
            },
            .directory => {
                // Skip modules we don't need for core encode/decode to avoid extra deps:
                // reflection (requires descriptor.upb), json/text/util/conformance.
                if (std.mem.eql(u8, entry.name, "conformance")) continue;
                if (std.mem.eql(u8, entry.name, "reflection")) continue;
                if (std.mem.eql(u8, entry.name, "json")) continue;
                if (std.mem.eql(u8, entry.name, "text")) continue;
                if (std.mem.eql(u8, entry.name, "util")) continue;
                const sub_path = std.fs.path.join(b.allocator, &.{ dir_path, entry.name }) catch continue;
                defer b.allocator.free(sub_path);
                addCSourcesRecursively(b, comp, sub_path);
            },
            else => {},
        }
    }
}

fn collectProtoFiles(
    b: *std.Build,
    dir_path: []const u8,
    out: *std.ArrayListUnmanaged([]const u8),
) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .file => {
                if (std.mem.endsWith(u8, entry.name, ".proto")) {
                    const full = try std.fs.path.join(b.allocator, &.{ dir_path, entry.name });
                    try out.append(b.allocator, full);
                }
            },
            .directory => {
                const sub = try std.fs.path.join(b.allocator, &.{ dir_path, entry.name });
                defer b.allocator.free(sub);
                try collectProtoFiles(b, sub, out);
            },
            else => {},
        }
    }
}

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) !void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // Get dependencies
    const logz = b.dependency("logz", .{
        .target = target,
        .optimize = optimize,
    });
    const metrics = b.dependency("metrics", .{
        .target = target,
        .optimize = optimize,
    });
    const toml = b.dependency("toml", .{
        .target = target,
        .optimize = optimize,
    });
    // const grpc_zig = b.dependency("grpc_zig", .{
    //     .target = target,
    //     .optimize = optimize,
    // });

    const protobuf_dep = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });

    // Build options (feature flags)
    const opt_pd_http_debug = b.option(bool, "pd_http_debug", "Enable PD HTTP JSON debug logging") orelse false;
    const build_opts = b.addOptions();
    build_opts.addOption(bool, "pd_http_debug", opt_pd_http_debug);

    const mod = b.addModule("client_zig", .{
        .root_source_file = b.path("src/root.zig"),

        .target = target,
        .imports = &.{
            .{ .name = "logz", .module = logz.module("logz") },
            .{ .name = "metrics", .module = metrics.module("metrics") },
            .{ .name = "toml", .module = toml.module("toml") },
            // Generated protobuf bindings depend on the external protobuf module
            .{ .name = "protobuf", .module = protobuf_dep.module("protobuf") },
            // .{ .name = "grpc_zig", .module = grpc_zig.module("grpc_zig") },
        },
    });
    mod.addOptions("build_options", build_opts);

    // Link local OpenSSL for TLS support
    const openssl_path = "third_party/openssl-build";
    mod.addIncludePath(b.path(openssl_path ++ "/include"));
    mod.addLibraryPath(b.path(openssl_path ++ "/lib"));
    mod.linkSystemLibrary("ssl", .{});
    mod.linkSystemLibrary("crypto", .{});
    // Link system zlib for compression wrapper
    mod.linkSystemLibrary("z", .{});

    const exe = b.addExecutable(.{
        .name = "client_zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),

            .target = target,
            .optimize = optimize,

            .imports = &.{
                .{ .name = "client_zig", .module = mod },
                // .{ .name = "grpc_zig", .module = grpc_zig.module("grpc_zig") },
            },
        }),
    });
    exe.root_module.addOptions("build_options", build_opts);

    exe.root_module.addImport("protobuf", protobuf_dep.module("protobuf"));

    // Link local OpenSSL for the executable as well
    exe.addIncludePath(b.path(openssl_path ++ "/include"));
    exe.addLibraryPath(b.path(openssl_path ++ "/lib"));
    exe.linkSystemLibrary("ssl");
    exe.linkSystemLibrary("crypto");
    exe.linkSystemLibrary("z");
    exe.linkLibC();

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    mod_tests.root_module.addOptions("build_options", build_opts);

    // Link OpenSSL for module tests
    mod_tests.addIncludePath(b.path(openssl_path ++ "/include"));
    mod_tests.addLibraryPath(b.path(openssl_path ++ "/lib"));
    mod_tests.linkSystemLibrary("ssl");
    mod_tests.linkSystemLibrary("crypto");
    mod_tests.linkSystemLibrary("z");
    mod_tests.linkLibC();

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    exe_tests.root_module.addOptions("build_options", build_opts);

    // Link OpenSSL for executable tests
    exe_tests.addIncludePath(b.path(openssl_path ++ "/include"));
    exe_tests.addLibraryPath(b.path(openssl_path ++ "/lib"));
    exe_tests.linkSystemLibrary("ssl");
    exe_tests.linkSystemLibrary("crypto");
    exe_tests.linkSystemLibrary("z");
    exe_tests.linkLibC();

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // Add protobuf generation step using external zig-protobuf
    const gen_proto = b.step("gen-proto", "Generate Zig protobuf files from kvproto");

    // Get all proto files from kvproto source
    const kvproto_proto_dir = "third_party/_kvproto_src/proto";
    const kvproto_include_dir = "third_party/_kvproto_src/include";

    // Build the full list of .proto sources (split: main proto vs include proto)
    var proto_list_main: std.ArrayListUnmanaged([]const u8) = .empty;
    var proto_list_inc: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        // No need to free the strings; the build graph can keep them,
        // but free the containers to be tidy.
        proto_list_main.deinit(b.allocator);
        proto_list_inc.deinit(b.allocator);
    }

    try collectProtoFiles(b, kvproto_proto_dir, &proto_list_main);
    try collectProtoFiles(b, kvproto_include_dir, &proto_list_inc);

    const protoc_step_main = protobuf.RunProtocStep.create(b, protobuf_dep.builder, target, .{
        .destination_directory = b.path("generated/proto"),
        .source_files = proto_list_main.items,
        .include_directories = &.{
            kvproto_proto_dir,
            kvproto_include_dir,
        },
    });

    // Second protoc step: generate kvproto/include -> src/proto/include (for organization/tracking)
    const protoc_step_inc = protobuf.RunProtocStep.create(b, protobuf_dep.builder, target, .{
        .destination_directory = b.path("generated/proto/include"),
        .source_files = proto_list_inc.items,
        .include_directories = &.{
            kvproto_proto_dir,
            kvproto_include_dir,
        },
    });

    gen_proto.dependOn(&protoc_step_main.step);
    gen_proto.dependOn(&protoc_step_inc.step);
    
    // Expose generated/proto directory as a Zig module named "kvproto"
    const kvproto_module = b.createModule(.{
        .root_source_file = b.path("generated/proto/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    kvproto_module.addImport("protobuf", protobuf_dep.module("protobuf"));

    // Make sure anything that needs the generated files can import "kvproto"
    mod.addImport("kvproto", kvproto_module);
    exe.root_module.addImport("kvproto", kvproto_module);
    
    // Make gen-proto opt-in. By default, do NOT regenerate during normal builds/tests.
    // Use: zig build gen-proto  or  zig build test -Dgen-proto=true
    const opt_run_gen_proto = b.option(bool, "gen-proto", "Run protoc to (re)generate kvproto bindings before build") orelse false;
    if (opt_run_gen_proto) {
        exe.step.dependOn(gen_proto);
        run_cmd.step.dependOn(gen_proto);
        mod_tests.step.dependOn(gen_proto);
        exe_tests.step.dependOn(gen_proto);
    }
    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
