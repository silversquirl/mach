const std = @import("std");
const Builder = std.build.Builder;
//const glfw = @import("../glfw/build.zig");
const glfw = @import("./libs/dawn/mach-old/glfw/build.zig"); // TODO: mach-old path

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    var main_tests = b.addTest("src/dummy.zig");
    main_tests.setBuildMode(mode);
    main_tests.setTarget(target);
    link(b, main_tests, .{});


    const example = b.addExecutable("hello_triangle", "examples/hello_triangle.zig");
    example.setBuildMode(mode);
    example.setTarget(target);
    link(b, example, .{});
    glfw.link(b, example, .{.system_sdk = .{.set_sysroot = false}});
    example.addPackagePath("glfw", "./libs/dawn/mach-old/glfw/src/main.zig"); // TODO: mach-old path
    example.addIncludeDir("out/Debug/gen/src/include");
    example.addIncludeDir("out/Debug/gen/src");
    example.addIncludeDir("examples");
    example.addIncludeDir("mach/glfw/upstream/glfw/include");
    example.addIncludeDir("src/include");
    example.install();
}

pub const LinuxWindowManager = enum {
    X11,
    Wayland,
};

pub const Options = struct {
    /// Only respected on Linux.
    linux_window_manager: LinuxWindowManager = .X11,

    /// Only respected on Windows. Whether or not to build a UWP application, linking WindowsApp.lib
    /// instead of user32.lib.
    windows_uwp_app: bool = false,

    /// Only respected on Windows.
    d3d12: bool = true,

    /// Only respected on MacOS.
    metal: bool = true,
};

pub fn link(b: *Builder, step: *std.build.LibExeObjStep, options: Options) void {
    const lib = buildLibrary(b, step, options);
    step.linkLibrary(lib);
}

fn buildLibrary(b: *Builder, step: *std.build.LibExeObjStep, options: Options) *std.build.LibExeObjStep {
    var main_abs = std.fs.path.join(b.allocator, &.{ thisDir(), "src/dawn/dummy.zig" }) catch unreachable;
    const lib = b.addStaticLibrary("dawn", main_abs);
    lib.setBuildMode(step.build_mode);
    lib.setTarget(step.target);

    const target = (std.zig.system.NativeTargetInfo.detect(b.allocator, step.target) catch unreachable).target;

    lib.addCSourceFile("src/dawn/dawn_native_c.cpp", &.{
        include("out/Debug/gen/src/include"),
        include("out/Debug/gen/src"),
        include("src/include"),
        include("src"),
        include("examples"),
    });

    lib.linkLibCpp(); // TODO: is it actually needed if we build with Zig?
    glfw.link(b, lib, .{.system_sdk = .{.set_sysroot = false}});
    addCommonSources(b, lib, options, target);
    addDawnPlatformSources(b, lib, options);
    addDawnNativeSources(b, lib, options, target);
    addDawnWireSources(b, lib, options, target);
    addDawnUtilsSources(b, lib, options, target);
    addThirdPartyTintSources(b, lib, options, target);
    return lib;
}

// Adds common sources; derived from src/common/BUILD.gn
fn addCommonSources(b: *Builder, step: *std.build.LibExeObjStep, options: Options, target: std.Target) void {
    _ = options;
    for ([_][]const u8{
        "src/common/Assert.cpp",
        "src/common/DynamicLib.cpp",
        "src/common/GPUInfo.cpp",
        "src/common/Log.cpp",
        "src/common/Math.cpp",
        "src/common/RefCounted.cpp",
        "src/common/Result.cpp",
        "src/common/SlabAllocator.cpp",
        "src/common/SystemUtils.cpp",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, &.{include("src")});
    }

    if (target.os.tag == .macos) {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn/src/common/SystemUtils_mac.mm" }) catch unreachable;
        step.addCSourceFile(abs_path, &.{include("src")});
    }
}


// Adds dawn platform sources; derived from src/dawn_platform/BUILD.gn
fn addDawnPlatformSources(b: *Builder, step: *std.build.LibExeObjStep, options: Options) void {
    _ = options;
    for ([_][]const u8{
        "src/dawn_platform/DawnPlatform.cpp",
        "src/dawn_platform/WorkerThread.cpp",
        "src/dawn_platform/tracing/EventTracer.cpp",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, &.{
            include("src"),
            include("src/include"),

            // TODO: should we commit generated dawn/webgpu.h somewhere to avoid people needing depot_tools (ninja, gn, gclient, etc.)
            include("out/Debug/gen/src/include"),
        });
    }
}

// Adds dawn native sources; derived from src/dawn_native/BUILD.gn
fn addDawnNativeSources(b: *Builder, step: *std.build.LibExeObjStep, options: Options, target: std.Target) void {
    AddThirdPartyAbseilCppSources(b, step, options, target);
    const flags = &.{
        "-DDAWN_ENABLE_BACKEND_METAL",
        //"-DDAWN_ENABLE_BACKEND_NULL",
        include("src"),
        include("src/include"),
        include("third_party/vulkan-deps/spirv-tools/src/include"),
        include("third_party/abseil-cpp"),

        "-DTINT_BUILD_SPV_READER=1",
        "-DTINT_BUILD_SPV_WRITER=1",
        "-DTINT_BUILD_WGSL_READER=1",
        "-DTINT_BUILD_WGSL_WRITER=1",
        "-DTINT_BUILD_MSL_WRITER=1",
        "-DTINT_BUILD_HLSL_WRITER=1",
        include("third_party/tint"),
        include("third_party/tint/include"),

        // TODO: should we commit generated dawn/webgpu.h somewhere to avoid people needing depot_tools (ninja, gn, gclient, etc.)
        include("out/Debug/gen/src/include"),
        include("out/Debug/gen/src"),
    };

    // #if defined(DAWN_ENABLE_BACKEND_D3D12)
    // #if defined(DAWN_ENABLE_BACKEND_METAL)
    // #if defined(DAWN_ENABLE_BACKEND_VULKAN)
    // #if defined(DAWN_ENABLE_BACKEND_DESKTOP_GL)
    // #if defined(DAWN_ENABLE_BACKEND_OPENGLES)
    // #if defined(DAWN_ENABLE_BACKEND_NULL)

    for ([_][]const u8{
        "out/Debug/gen/src/dawn/dawn_thread_dispatch_proc.cpp",
        "out/Debug/gen/src/dawn/dawn_proc.c",
        "out/Debug/gen/src/dawn/webgpu_cpp.cpp",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    for ([_][]const u8{
        "src/dawn_native/Adapter.cpp",
        "src/dawn_native/AsyncTask.cpp",
        "src/dawn_native/AttachmentState.cpp",
        "src/dawn_native/BackendConnection.cpp",
        "src/dawn_native/BindGroup.cpp",
        "src/dawn_native/BindGroupLayout.cpp",
        "src/dawn_native/BindingInfo.cpp",
        "src/dawn_native/BuddyAllocator.cpp",
        "src/dawn_native/BuddyMemoryAllocator.cpp",
        "src/dawn_native/Buffer.cpp",
        "src/dawn_native/BufferLocation.cpp",
        "src/dawn_native/CachedObject.cpp",
        "src/dawn_native/CallbackTaskManager.cpp",
        "src/dawn_native/CommandAllocator.cpp",
        "src/dawn_native/CommandBuffer.cpp",
        "src/dawn_native/CommandBufferStateTracker.cpp",
        "src/dawn_native/CommandEncoder.cpp",
        "src/dawn_native/CommandValidation.cpp",
        "src/dawn_native/Commands.cpp",
        "src/dawn_native/CompilationMessages.cpp",
        "src/dawn_native/ComputePassEncoder.cpp",
        "src/dawn_native/ComputePipeline.cpp",
        "src/dawn_native/CopyTextureForBrowserHelper.cpp",
        "src/dawn_native/CreatePipelineAsyncTask.cpp",
        "src/dawn_native/Device.cpp",
        "src/dawn_native/DynamicUploader.cpp",
        "src/dawn_native/EncodingContext.cpp",
        "src/dawn_native/Error.cpp",
        "src/dawn_native/ErrorData.cpp",
        "src/dawn_native/ErrorInjector.cpp",
        "src/dawn_native/ErrorScope.cpp",
        "src/dawn_native/Extensions.cpp",
        "src/dawn_native/ExternalTexture.cpp",
        "src/dawn_native/Format.cpp",
        "src/dawn_native/IndirectDrawMetadata.cpp",
        "src/dawn_native/IndirectDrawValidationEncoder.cpp",
        "src/dawn_native/Instance.cpp",
        "src/dawn_native/InternalPipelineStore.cpp",
        "src/dawn_native/Limits.cpp",
        "src/dawn_native/ObjectBase.cpp",
        "src/dawn_native/ObjectContentHasher.cpp",
        "src/dawn_native/PassResourceUsageTracker.cpp",
        "src/dawn_native/PerStage.cpp",
        "src/dawn_native/PersistentCache.cpp",
        "src/dawn_native/Pipeline.cpp",
        "src/dawn_native/PipelineLayout.cpp",
        "src/dawn_native/PooledResourceMemoryAllocator.cpp",
        "src/dawn_native/ProgrammablePassEncoder.cpp",
        "src/dawn_native/QueryHelper.cpp",
        "src/dawn_native/QuerySet.cpp",
        "src/dawn_native/Queue.cpp",
        "src/dawn_native/RenderBundle.cpp",
        "src/dawn_native/RenderBundleEncoder.cpp",
        "src/dawn_native/RenderEncoderBase.cpp",
        "src/dawn_native/RenderPassEncoder.cpp",
        "src/dawn_native/RenderPipeline.cpp",
        "src/dawn_native/ResourceMemoryAllocation.cpp",
        "src/dawn_native/RingBufferAllocator.cpp",
        "src/dawn_native/Sampler.cpp",
        "src/dawn_native/ScratchBuffer.cpp",
        "src/dawn_native/ShaderModule.cpp",
        "src/dawn_native/StagingBuffer.cpp",
        "src/dawn_native/Subresource.cpp",
        "src/dawn_native/Surface.cpp",
        "src/dawn_native/SwapChain.cpp",
        "src/dawn_native/Texture.cpp",
        "src/dawn_native/TintUtils.cpp",
        "src/dawn_native/Toggles.cpp",
        "src/dawn_native/VertexFormat.cpp",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    // dawn_native_utils_gen
    for ([_][]const u8{
        "out/Debug/gen/src/dawn_native/ChainUtils_autogen.cpp",
        "out/Debug/gen/src/dawn_native/ProcTable.cpp",
        "out/Debug/gen/src/dawn_native/wgpu_structs_autogen.cpp",
        "out/Debug/gen/src/dawn_native/ValidationUtils_autogen.cpp",
        "out/Debug/gen/src/dawn_native/webgpu_absl_format_autogen.cpp",
        "out/Debug/gen/src/dawn_native/ObjectType_autogen.cpp",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    // TODO: could allow enable_vulkan_validation_layers here. See src/dawn_native/BUILD.gn
    // TODO: allow use_angle here. See src/dawn_native/BUILD.gn
    // TODO: could allow use_swiftshader here. See src/dawn_native/BUILD.gn
    // TODO: allow dawn_enable_vulkan here. See src/dawn_native/BUILD.gn
    // TODO: allow dawn_enable_opengl here. See src/dawn_native/BUILD.gn
    // TODO: could allow dawn_use_spriv_cross here. See src/dawn_native/BUILD.gn

    switch (target.os.tag) {
        .windows => {
            if (options.windows_uwp_app) {
                if (step.build_mode == .Debug) {
                    // DXGIGetDebugInterface1 is defined in dxgi.lib
                    // But this API is tagged as a development-only capability
                    // which implies that linking to this function will cause
                    // the application to fail Windows store certification
                    // So we only link to it in debug build when compiling for UWP.
                    // In win32 we load dxgi.dll using LoadLibrary
                    // so no need for static linking.
                    step.linkSystemLibrary("dxgi.lib");
                }
                step.linkSystemLibrary("user32.lib");
            }

            // TODO:
            //   if (dawn_enable_d3d12) {
            //     libs += [ "dxguid.lib" ]
            //     sources += [
            //       "d3d12/AdapterD3D12.cpp",
            //       "d3d12/BackendD3D12.cpp",
            //       "d3d12/BindGroupD3D12.cpp",
            //       "d3d12/BindGroupLayoutD3D12.cpp",
            //       "d3d12/BufferD3D12.cpp",
            //       "d3d12/CPUDescriptorHeapAllocationD3D12.cpp",
            //       "d3d12/CommandAllocatorManager.cpp",
            //       "d3d12/CommandBufferD3D12.cpp",
            //       "d3d12/CommandRecordingContext.cpp",
            //       "d3d12/ComputePipelineD3D12.cpp",
            //       "d3d12/D3D11on12Util.cpp",
            //       "d3d12/D3D12Error.cpp",
            //       "d3d12/D3D12Info.cpp",
            //       "d3d12/DeviceD3D12.cpp",
            //       "d3d12/GPUDescriptorHeapAllocationD3D12.cpp",
            //       "d3d12/HeapAllocatorD3D12.cpp",
            //       "d3d12/HeapD3D12.cpp",
            //       "d3d12/NativeSwapChainImplD3D12.cpp",
            //       "d3d12/PageableD3D12.cpp",
            //       "d3d12/PipelineLayoutD3D12.cpp",
            //       "d3d12/PlatformFunctions.cpp",
            //       "d3d12/QuerySetD3D12.cpp",
            //       "d3d12/QueueD3D12.cpp",
            //       "d3d12/RenderPassBuilderD3D12.cpp",
            //       "d3d12/RenderPipelineD3D12.cpp",
            //       "d3d12/ResidencyManagerD3D12.cpp",
            //       "d3d12/ResourceAllocatorManagerD3D12.cpp",
            //       "d3d12/ResourceHeapAllocationD3D12.cpp",
            //       "d3d12/SamplerD3D12.cpp",
            //       "d3d12/SamplerHeapCacheD3D12.cpp",
            //       "d3d12/ShaderModuleD3D12.cpp",
            //       "d3d12/ShaderVisibleDescriptorAllocatorD3D12.cpp",
            //       "d3d12/StagingBufferD3D12.cpp",
            //       "d3d12/StagingDescriptorAllocatorD3D12.cpp",
            //       "d3d12/SwapChainD3D12.cpp",
            //       "d3d12/TextureCopySplitter.cpp",
            //       "d3d12/TextureD3D12.cpp",
            //       "d3d12/UtilsD3D12.cpp",
            //     ]
            //   }
        },
        .macos => {
            if (options.metal) {
                step.linkFramework("Metal");
                step.linkFramework("CoreGraphics");
                step.linkFramework("Foundation");
                // step.linkFramework("Cocoa");
                step.linkFramework("IOKit");
                step.linkFramework("IOSurface");
                step.linkFramework("QuartzCore");

                for ([_][]const u8{
                    "src/dawn_native/metal/MetalBackend.mm",
                    "src/dawn_native/Surface_metal.mm",
                    "src/dawn_native/metal/BackendMTL.mm",
                    "src/dawn_native/metal/BindGroupLayoutMTL.mm",
                    "src/dawn_native/metal/BindGroupMTL.mm",
                    "src/dawn_native/metal/BufferMTL.mm",
                    "src/dawn_native/metal/CommandBufferMTL.mm",
                    "src/dawn_native/metal/CommandRecordingContext.mm",
                    "src/dawn_native/metal/ComputePipelineMTL.mm",
                    "src/dawn_native/metal/DeviceMTL.mm",
                    "src/dawn_native/metal/PipelineLayoutMTL.mm",
                    "src/dawn_native/metal/QuerySetMTL.mm",
                    "src/dawn_native/metal/QueueMTL.mm",
                    "src/dawn_native/metal/RenderPipelineMTL.mm",
                    "src/dawn_native/metal/SamplerMTL.mm",
                    "src/dawn_native/metal/ShaderModuleMTL.mm",
                    "src/dawn_native/metal/StagingBufferMTL.mm",
                    "src/dawn_native/metal/SwapChainMTL.mm",
                    "src/dawn_native/metal/TextureMTL.mm",
                    "src/dawn_native/metal/UtilsMetal.mm",
                }) |path| {
                    var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
                    step.addCSourceFile(abs_path, flags);
                }
            }
        },
        else => {
            if (options.linux_window_manager == .X11) {
                step.linkSystemLibrary("X11");
                for ([_][]const u8{
                    "src/dawn_native/XlibXcbFunctions.cpp",
                }) |path| {
                    var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
                    step.addCSourceFile(abs_path, flags);
                }
            }
        },
    }

    for ([_][]const u8{
        "src/dawn_native/null/DeviceNull.cpp",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    // TODO: no vulkan on macos
    // TODO:
    //   if (dawn_enable_opengl || dawn_enable_vulkan) {
    //     sources += [
    //       "SpirvValidation.cpp",
    //     ]
    //   }

    // TODO:
    //   if (dawn_enable_opengl) {
    //     public_deps += [
    //       ":dawn_native_opengl_loader_gen",
    //       "${dawn_root}/third_party/khronos:khronos_platform",
    //     ]
    //     sources += get_target_outputs(":dawn_native_opengl_loader_gen")
    //     sources += [
    //       "opengl/BackendGL.cpp",
    //       "opengl/BindGroupGL.cpp",
    //       "opengl/BindGroupLayoutGL.cpp",
    //       "opengl/BufferGL.cpp",
    //       "opengl/CommandBufferGL.cpp",
    //       "opengl/ComputePipelineGL.cpp",
    //       "opengl/DeviceGL.cpp",
    //       "opengl/GLFormat.cpp",
    //       "opengl/NativeSwapChainImplGL.cpp",
    //       "opengl/OpenGLFunctions.cpp",
    //       "opengl/OpenGLVersion.cpp",
    //       "opengl/PersistentPipelineStateGL.cpp",
    //       "opengl/PipelineGL.cpp",
    //       "opengl/PipelineLayoutGL.cpp",
    //       "opengl/QuerySetGL.cpp",
    //       "opengl/QueueGL.cpp",
    //       "opengl/RenderPipelineGL.cpp",
    //       "opengl/SamplerGL.cpp",
    //       "opengl/ShaderModuleGL.cpp",
    //       "opengl/SpirvUtils.cpp",
    //       "opengl/SwapChainGL.cpp",
    //       "opengl/TextureGL.cpp",
    //       "opengl/UtilsGL.cpp",
    //     ]
    //   }

    // TODO: no vulkan on macos
    // TODO:
    //   if (dawn_enable_vulkan) {
    //     public_deps += [ "${dawn_root}/third_party/khronos:vulkan_headers" ]
    //     sources += [
    //       "vulkan/AdapterVk.cpp",
    //       "vulkan/BackendVk.cpp",
    //       "vulkan/BindGroupLayoutVk.cpp",
    //       "vulkan/BindGroupVk.cpp",
    //       "vulkan/BufferVk.cpp",
    //       "vulkan/CommandBufferVk.cpp",
    //       "vulkan/ComputePipelineVk.cpp",
    //       "vulkan/DescriptorSetAllocator.cpp",
    //       "vulkan/DeviceVk.cpp",
    //       "vulkan/FencedDeleter.cpp",
    //       "vulkan/NativeSwapChainImplVk.cpp",
    //       "vulkan/PipelineLayoutVk.cpp",
    //       "vulkan/QuerySetVk.cpp",
    //       "vulkan/QueueVk.cpp",
    //       "vulkan/RenderPassCache.cpp",
    //       "vulkan/RenderPipelineVk.cpp",
    //       "vulkan/ResourceHeapVk.cpp",
    //       "vulkan/ResourceMemoryAllocatorVk.cpp",
    //       "vulkan/SamplerVk.cpp",
    //       "vulkan/ShaderModuleVk.cpp",
    //       "vulkan/StagingBufferVk.cpp",
    //       "vulkan/SwapChainVk.cpp",
    //       "vulkan/TextureVk.cpp",
    //       "vulkan/UtilsVulkan.cpp",
    //       "vulkan/VulkanError.cpp",
    //       "vulkan/VulkanExtensions.cpp",
    //       "vulkan/VulkanFunctions.cpp",
    //       "vulkan/VulkanInfo.cpp",
    //     ]

    // TODO:
    //     if (is_chromeos) {
    //       sources += [
    //         "vulkan/external_memory/MemoryServiceDmaBuf.cpp",
    //         "vulkan/external_semaphore/SemaphoreServiceFD.cpp",
    //       ]
    //       defines += [ "DAWN_USE_SYNC_FDS" ]
    //     } else if (is_linux) {
    //       sources += [
    //         "vulkan/external_memory/MemoryServiceOpaqueFD.cpp",
    //         "vulkan/external_semaphore/SemaphoreServiceFD.cpp",
    //       ]
    //     } else if (is_fuchsia) {
    //       sources += [
    //         "vulkan/external_memory/MemoryServiceZirconHandle.cpp",
    //         "vulkan/external_semaphore/SemaphoreServiceZirconHandle.cpp",
    //       ]
    //     } else {
    //       sources += [
    //         "vulkan/external_memory/MemoryServiceNull.cpp",
    //         "vulkan/external_semaphore/SemaphoreServiceNull.cpp",
    //       ]
    //     }

    // TODO: could add is_fuchsia checks if anybody cares about Fuchsia?

    // TODO:
    //     if (enable_vulkan_validation_layers) {
    //       defines += [
    //         "DAWN_ENABLE_VULKAN_VALIDATION_LAYERS",
    //         "DAWN_VK_DATA_DIR=\"$vulkan_data_subdir\"",
    //       ]
    //     }
    //     if (enable_vulkan_loader) {
    //       data_deps += [ "${dawn_vulkan_loader_dir}:libvulkan" ]
    //     }
    //     if (use_swiftshader) {
    //       data_deps += [
    //         "${dawn_swiftshader_dir}/src/Vulkan:icd_file",
    //         "${dawn_swiftshader_dir}/src/Vulkan:swiftshader_libvulkan",
    //       ]
    //       defines += [
    //         "DAWN_ENABLE_SWIFTSHADER",
    //         "DAWN_SWIFTSHADER_VK_ICD_JSON=\"${swiftshader_icd_file_name}\"",
    //       ]
    //     }
    //   }

    // TODO:
    //   if (use_angle) {
    //     data_deps += [
    //       "${dawn_angle_dir}:libEGL",
    //       "${dawn_angle_dir}:libGLESv2",
    //     ]
    //   }
    // }

    // TODO: ???
    // # The static and shared libraries for dawn_native. Most of the files are
    // # already compiled in dawn_native_sources, but we still need to compile
    // # files defining exported symbols.
    // dawn_component("dawn_native") {
    //   DEFINE_PREFIX = "DAWN_NATIVE"

    //   #Make headers publically visible
    //   public_deps = [ ":dawn_native_headers" ]

    for ([_][]const u8{
        "src/dawn_native/DawnNative.cpp",
        "src/dawn_native/null/NullBackend.cpp",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    //   if (dawn_enable_d3d12) {
    //     sources += [ "d3d12/D3D12Backend.cpp" ]
    //   }
    //   if (dawn_enable_opengl) {
    //     sources += [ "opengl/OpenGLBackend.cpp" ]
    //   }
    //   if (dawn_enable_vulkan) {
    //     sources += [ "vulkan/VulkanBackend.cpp" ]

    //     if (enable_vulkan_validation_layers) {
    //       data_deps =
    //           [ "${dawn_vulkan_validation_layers_dir}:vulkan_validation_layers" ]
    //       if (!is_android) {
    //         data_deps +=
    //             [ "${dawn_vulkan_validation_layers_dir}:vulkan_gen_json_files" ]
    //       }
    //     }
    //   }
    // }
}

// Adds third party tint sources; derived from third_party/tint/src/BUILD.gn
fn addThirdPartyTintSources(b: *Builder, step: *std.build.LibExeObjStep, options: Options, target: std.Target) void {
    addThirdPartyVulkanDepsSPIRVTools(b, step, options, target);
    const flags = &.{
        "-DTINT_BUILD_SPV_READER=1",
        "-DTINT_BUILD_SPV_WRITER=1",
        "-DTINT_BUILD_WGSL_READER=1",
        "-DTINT_BUILD_WGSL_WRITER=1",
        "-DTINT_BUILD_MSL_WRITER=1",
        "-DTINT_BUILD_HLSL_WRITER=1",

        // Required for TINT_BUILD_SPV_READER=1 and TINT_BUILD_SPV_WRITER=1
        include("third_party/vulkan-deps"),
        include("third_party/vulkan-deps/spirv-tools/src"),
        include("third_party/vulkan-deps/spirv-tools/src/include"),
        include("third_party/vulkan-deps/spirv-headers/src/include"),
        include("out/Debug/gen/third_party/vulkan-deps/spirv-tools/src"),
        include("out/Debug/gen/third_party/vulkan-deps/spirv-tools/src/include"),
        include("third_party/tint"),
        include("third_party/tint/include"),
    };

    // libtint_core_all_src
    for ([_][]const u8{
        "third_party/tint/src/ast/access.cc",
        "third_party/tint/src/ast/alias.cc",
        "third_party/tint/src/ast/array.cc",
        "third_party/tint/src/ast/array_accessor_expression.cc",
        "third_party/tint/src/ast/assignment_statement.cc",
        "third_party/tint/src/ast/ast_type.cc",
        "third_party/tint/src/ast/atomic.cc",
        "third_party/tint/src/ast/binary_expression.cc",
        "third_party/tint/src/ast/binding_decoration.cc",
        "third_party/tint/src/ast/bitcast_expression.cc",
        "third_party/tint/src/ast/block_statement.cc",
        "third_party/tint/src/ast/bool.cc",
        "third_party/tint/src/ast/bool_literal.cc",
        "third_party/tint/src/ast/break_statement.cc",
        "third_party/tint/src/ast/builtin.cc",
        "third_party/tint/src/ast/builtin_decoration.cc",
        "third_party/tint/src/ast/call_expression.cc",
        "third_party/tint/src/ast/call_statement.cc",
        "third_party/tint/src/ast/case_statement.cc",
        "third_party/tint/src/ast/constructor_expression.cc",
        "third_party/tint/src/ast/continue_statement.cc",
        "third_party/tint/src/ast/decoration.cc",
        "third_party/tint/src/ast/depth_multisampled_texture.cc",
        "third_party/tint/src/ast/depth_texture.cc",
        "third_party/tint/src/ast/disable_validation_decoration.cc",
        "third_party/tint/src/ast/discard_statement.cc",
        "third_party/tint/src/ast/else_statement.cc",
        "third_party/tint/src/ast/expression.cc",
        "third_party/tint/src/ast/external_texture.cc",
        "third_party/tint/src/ast/f32.cc",
        "third_party/tint/src/ast/fallthrough_statement.cc",
        "third_party/tint/src/ast/float_literal.cc",
        "third_party/tint/src/ast/for_loop_statement.cc",
        "third_party/tint/src/ast/function.cc",
        "third_party/tint/src/ast/group_decoration.cc",
        "third_party/tint/src/ast/i32.cc",
        "third_party/tint/src/ast/identifier_expression.cc",
        "third_party/tint/src/ast/if_statement.cc",
        "third_party/tint/src/ast/int_literal.cc",
        "third_party/tint/src/ast/internal_decoration.cc",
        "third_party/tint/src/ast/interpolate_decoration.cc",
        "third_party/tint/src/ast/invariant_decoration.cc",
        "third_party/tint/src/ast/literal.cc",
        "third_party/tint/src/ast/location_decoration.cc",
        "third_party/tint/src/ast/loop_statement.cc",
        "third_party/tint/src/ast/matrix.cc",
        "third_party/tint/src/ast/member_accessor_expression.cc",
        "third_party/tint/src/ast/module.cc",
        "third_party/tint/src/ast/multisampled_texture.cc",
        "third_party/tint/src/ast/node.cc",
        "third_party/tint/src/ast/override_decoration.cc",
        "third_party/tint/src/ast/pipeline_stage.cc",
        "third_party/tint/src/ast/pointer.cc",
        "third_party/tint/src/ast/return_statement.cc",
        "third_party/tint/src/ast/sampled_texture.cc",
        "third_party/tint/src/ast/sampler.cc",
        "third_party/tint/src/ast/scalar_constructor_expression.cc",
        "third_party/tint/src/ast/sint_literal.cc",
        "third_party/tint/src/ast/stage_decoration.cc",
        "third_party/tint/src/ast/statement.cc",
        "third_party/tint/src/ast/storage_class.cc",
        "third_party/tint/src/ast/storage_texture.cc",
        "third_party/tint/src/ast/stride_decoration.cc",
        "third_party/tint/src/ast/struct.cc",
        "third_party/tint/src/ast/struct_block_decoration.cc",
        "third_party/tint/src/ast/struct_member.cc",
        "third_party/tint/src/ast/struct_member_align_decoration.cc",
        "third_party/tint/src/ast/struct_member_offset_decoration.cc",
        "third_party/tint/src/ast/struct_member_size_decoration.cc",
        "third_party/tint/src/ast/switch_statement.cc",
        "third_party/tint/src/ast/texture.cc",
        "third_party/tint/src/ast/type_constructor_expression.cc",
        "third_party/tint/src/ast/type_decl.cc",
        "third_party/tint/src/ast/type_name.cc",
        "third_party/tint/src/ast/u32.cc",
        "third_party/tint/src/ast/uint_literal.cc",
        "third_party/tint/src/ast/unary_op.cc",
        "third_party/tint/src/ast/unary_op_expression.cc",
        "third_party/tint/src/ast/variable.cc",
        "third_party/tint/src/ast/variable_decl_statement.cc",
        "third_party/tint/src/ast/vector.cc",
        "third_party/tint/src/ast/void.cc",
        "third_party/tint/src/ast/workgroup_decoration.cc",
        "third_party/tint/src/castable.cc",
        "third_party/tint/src/clone_context.cc",
        "third_party/tint/src/debug.cc",
        "third_party/tint/src/demangler.cc",
        "third_party/tint/src/diagnostic/diagnostic.cc",
        "third_party/tint/src/diagnostic/formatter.cc",
        "third_party/tint/src/diagnostic/printer.cc",
        "third_party/tint/src/inspector/entry_point.cc",
        "third_party/tint/src/inspector/inspector.cc",
        "third_party/tint/src/inspector/resource_binding.cc",
        "third_party/tint/src/inspector/scalar.cc",
        "third_party/tint/src/intrinsic_table.cc",
        "third_party/tint/src/program.cc",
        "third_party/tint/src/program_builder.cc",
        "third_party/tint/src/program_id.cc",
        "third_party/tint/src/reader/reader.cc",
        "third_party/tint/src/resolver/resolver.cc",
        "third_party/tint/src/resolver/resolver_constants.cc",
        "third_party/tint/src/source.cc",
        "third_party/tint/src/symbol.cc",
        "third_party/tint/src/symbol_table.cc",
        "third_party/tint/src/transform/add_empty_entry_point.cc",
        "third_party/tint/src/transform/array_length_from_uniform.cc",
        "third_party/tint/src/transform/binding_remapper.cc",
        "third_party/tint/src/transform/calculate_array_length.cc",
        "third_party/tint/src/transform/canonicalize_entry_point_io.cc",
        "third_party/tint/src/transform/decompose_memory_access.cc",
        "third_party/tint/src/transform/decompose_strided_matrix.cc",
        "third_party/tint/src/transform/external_texture_transform.cc",
        "third_party/tint/src/transform/first_index_offset.cc",
        "third_party/tint/src/transform/fold_constants.cc",
        "third_party/tint/src/transform/fold_trivial_single_use_lets.cc",
        "third_party/tint/src/transform/for_loop_to_loop.cc",
        "third_party/tint/src/transform/inline_pointer_lets.cc",
        "third_party/tint/src/transform/loop_to_for_loop.cc",
        "third_party/tint/src/transform/manager.cc",
        "third_party/tint/src/transform/module_scope_var_to_entry_point_param.cc",
        "third_party/tint/src/transform/num_workgroups_from_uniform.cc",
        "third_party/tint/src/transform/pad_array_elements.cc",
        "third_party/tint/src/transform/promote_initializers_to_const_var.cc",
        "third_party/tint/src/transform/renamer.cc",
        "third_party/tint/src/transform/robustness.cc",
        "third_party/tint/src/transform/simplify.cc",
        "third_party/tint/src/transform/single_entry_point.cc",
        "third_party/tint/src/transform/transform.cc",
        "third_party/tint/src/transform/vertex_pulling.cc",
        "third_party/tint/src/transform/wrap_arrays_in_structs.cc",
        "third_party/tint/src/transform/zero_init_workgroup_memory.cc",
        "third_party/tint/src/writer/append_vector.cc",
        "third_party/tint/src/writer/float_to_string.cc",
        "third_party/tint/src/writer/text.cc",
        "third_party/tint/src/writer/text_generator.cc",
        "third_party/tint/src/writer/writer.cc",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    switch (target.os.tag) {
        .windows => step.addCSourceFile(thisDir() ++ "/libs/dawn/third_party/tint/src/diagnostic/printer_windows.cc", flags),
        .linux => step.addCSourceFile(thisDir() ++ "/libs/dawn/third_party/tint/src/diagnostic/printer_linux.cc", flags),
        else => step.addCSourceFile(thisDir() ++ "/libs/dawn/third_party/tint/src/diagnostic/printer_other.cc", flags),
    }

    // libtint_sem_src
    for ([_][]const u8{
        "third_party/tint/src/sem/array.cc",
        "third_party/tint/src/sem/atomic_type.cc",
        "third_party/tint/src/sem/block_statement.cc",
        "third_party/tint/src/sem/bool_type.cc",
        "third_party/tint/src/sem/call.cc",
        "third_party/tint/src/sem/call_target.cc",
        "third_party/tint/src/sem/constant.cc",
        "third_party/tint/src/sem/depth_multisampled_texture_type.cc",
        "third_party/tint/src/sem/depth_texture_type.cc",
        "third_party/tint/src/sem/expression.cc",
        "third_party/tint/src/sem/external_texture_type.cc",
        "third_party/tint/src/sem/f32_type.cc",
        "third_party/tint/src/sem/for_loop_statement.cc",
        "third_party/tint/src/sem/function.cc",
        "third_party/tint/src/sem/i32_type.cc",
        "third_party/tint/src/sem/if_statement.cc",
        "third_party/tint/src/sem/info.cc",
        "third_party/tint/src/sem/intrinsic.cc",
        "third_party/tint/src/sem/intrinsic_type.cc",
        "third_party/tint/src/sem/loop_statement.cc",
        "third_party/tint/src/sem/matrix_type.cc",
        "third_party/tint/src/sem/member_accessor_expression.cc",
        "third_party/tint/src/sem/multisampled_texture_type.cc",
        "third_party/tint/src/sem/node.cc",
        "third_party/tint/src/sem/parameter_usage.cc",
        "third_party/tint/src/sem/pointer_type.cc",
        "third_party/tint/src/sem/reference_type.cc",
        "third_party/tint/src/sem/sampled_texture_type.cc",
        "third_party/tint/src/sem/sampler_type.cc",
        "third_party/tint/src/sem/statement.cc",
        "third_party/tint/src/sem/storage_texture_type.cc",
        "third_party/tint/src/sem/struct.cc",
        "third_party/tint/src/sem/switch_statement.cc",
        "third_party/tint/src/sem/texture_type.cc",
        "third_party/tint/src/sem/type.cc",
        "third_party/tint/src/sem/type_manager.cc",
        "third_party/tint/src/sem/u32_type.cc",
        "third_party/tint/src/sem/variable.cc",
        "third_party/tint/src/sem/vector_type.cc",
        "third_party/tint/src/sem/void_type.cc",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    // libtint_spv_reader_src
    for ([_][]const u8{
        "third_party/tint/src/reader/spirv/construct.cc",
        "third_party/tint/src/reader/spirv/entry_point_info.cc",
        "third_party/tint/src/reader/spirv/enum_converter.cc",
        "third_party/tint/src/reader/spirv/function.cc",
        "third_party/tint/src/reader/spirv/namer.cc",
        "third_party/tint/src/reader/spirv/parser.cc",
        "third_party/tint/src/reader/spirv/parser_impl.cc",
        "third_party/tint/src/reader/spirv/parser_type.cc",
        "third_party/tint/src/reader/spirv/usage.cc",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    // libtint_spv_writer_src
    for ([_][]const u8{
        "third_party/tint/src/writer/spirv/binary_writer.cc",
        "third_party/tint/src/writer/spirv/builder.cc",
        "third_party/tint/src/writer/spirv/function.cc",
        "third_party/tint/src/writer/spirv/generator.cc",
        "third_party/tint/src/writer/spirv/instruction.cc",
        "third_party/tint/src/writer/spirv/operand.cc",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    // libtint_wgsl_reader_src
    for ([_][]const u8{
        "third_party/tint/src/reader/wgsl/lexer.cc",
        "third_party/tint/src/reader/wgsl/parser.cc",
        "third_party/tint/src/reader/wgsl/parser_impl.cc",
        "third_party/tint/src/reader/wgsl/token.cc",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    // libtint_wgsl_writer_src
    for ([_][]const u8{
        "third_party/tint/src/writer/wgsl/generator.cc",
        "third_party/tint/src/writer/wgsl/generator_impl.cc",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    // libtint_msl_writer_src
    for ([_][]const u8{
        "third_party/tint/src/writer/msl/generator.cc",
        "third_party/tint/src/writer/msl/generator_impl.cc",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    // libtint_hlsl_writer_src
    for ([_][]const u8{
        "third_party/tint/src/writer/hlsl/generator.cc",
        "third_party/tint/src/writer/hlsl/generator_impl.cc",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }
}

// Adds third_party/vulkan-deps/spirv-tools sources; derived from third_party/vulkan-deps/spirv-tools/src/BUILD.gn
fn addThirdPartyVulkanDepsSPIRVTools(b: *Builder, step: *std.build.LibExeObjStep, options: Options, target: std.Target) void {
    _ = options;
    _ = target;
    const flags = &.{
        include("third_party/vulkan-deps/spirv-tools/src"),
        include("third_party/vulkan-deps/spirv-tools/src/include"),
        include("third_party/vulkan-deps/spirv-headers/src/include"),
        include("out/Debug/gen/third_party/vulkan-deps/spirv-tools/src"),
        include("out/Debug/gen/third_party/vulkan-deps/spirv-tools/src/include"),
    };

    // spvtools
    for ([_][]const u8{
        "third_party/vulkan-deps/spirv-tools/src/source/assembly_grammar.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/binary.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/diagnostic.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/disassemble.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/enum_string_mapping.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/ext_inst.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/extensions.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/libspirv.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/name_mapper.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opcode.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/operand.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/parsed_operand.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/print.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/spirv_endian.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/spirv_fuzzer_options.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/spirv_optimizer_options.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/spirv_reducer_options.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/spirv_target_env.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/spirv_validator_options.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/table.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/text.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/text_handler.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/util/bit_vector.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/util/parse_number.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/util/string_utils.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/util/timer.cpp",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    // spvtools_val
    for ([_][]const u8{
        "third_party/vulkan-deps/spirv-tools/src/source/val/basic_block.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/construct.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/function.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/instruction.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_adjacency.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_annotation.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_arithmetics.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_atomics.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_barriers.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_bitwise.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_builtins.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_capability.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_cfg.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_composites.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_constants.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_conversion.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_debug.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_decorations.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_derivatives.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_execution_limitations.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_extensions.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_function.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_id.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_image.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_instruction.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_interfaces.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_layout.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_literals.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_logicals.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_memory.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_memory_semantics.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_misc.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_mode_setting.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_non_uniform.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_primitives.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_scopes.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_small_type_uses.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validate_type.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/val/validation_state.cpp",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    // spvtools_opt
    for ([_][]const u8{
        "third_party/vulkan-deps/spirv-tools/src/source/opt/aggressive_dead_code_elim_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/amd_ext_to_khr.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/basic_block.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/block_merge_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/block_merge_util.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/build_module.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/ccp_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/cfg.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/cfg_cleanup_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/code_sink.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/combine_access_chains.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/compact_ids_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/composite.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/const_folding_rules.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/constants.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/control_dependence.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/convert_to_sampled_image_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/convert_to_half_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/copy_prop_arrays.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/dataflow.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/dead_branch_elim_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/dead_insert_elim_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/dead_variable_elimination.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/debug_info_manager.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/decoration_manager.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/def_use_manager.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/desc_sroa.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/dominator_analysis.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/dominator_tree.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/eliminate_dead_constant_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/eliminate_dead_functions_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/eliminate_dead_functions_util.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/eliminate_dead_members_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/feature_manager.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/fix_storage_class.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/flatten_decoration_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/fold.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/fold_spec_constant_op_and_composite_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/folding_rules.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/freeze_spec_constant_value_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/function.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/graphics_robust_access_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/if_conversion.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/inline_exhaustive_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/inline_opaque_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/inline_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/inst_bindless_check_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/inst_buff_addr_check_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/inst_debug_printf_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/instruction.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/instruction_list.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/instrument_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/interp_fixup_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/ir_context.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/ir_loader.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/licm_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/local_access_chain_convert_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/local_redundancy_elimination.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/local_single_block_elim_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/local_single_store_elim_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/loop_dependence.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/loop_dependence_helpers.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/loop_descriptor.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/loop_fission.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/loop_fusion.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/loop_fusion_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/loop_peeling.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/loop_unroller.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/loop_unswitch_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/loop_utils.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/mem_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/merge_return_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/module.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/optimizer.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/pass_manager.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/private_to_local_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/propagator.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/reduce_load_size.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/redundancy_elimination.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/register_pressure.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/relax_float_ops_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/remove_duplicates_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/remove_unused_interface_variables_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/replace_invalid_opc.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/scalar_analysis.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/scalar_analysis_simplification.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/scalar_replacement_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/set_spec_constant_default_value_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/simplification_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/ssa_rewrite_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/strength_reduction_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/strip_debug_info_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/strip_reflect_info_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/struct_cfg_analysis.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/type_manager.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/types.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/unify_const_pass.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/upgrade_memory_model.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/value_number_table.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/vector_dce.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/workaround1209.cpp",
        "third_party/vulkan-deps/spirv-tools/src/source/opt/wrap_opkill.cpp",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    // spvtools_link
    for ([_][]const u8{
        "third_party/vulkan-deps/spirv-tools/src/source/link/linker.cpp",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }
}

// Adds third_party/abseil sources; derived from:
//
// ```
// $ find third_party/abseil-cpp/absl | grep '\.cc' | grep -v 'test' | grep -v 'benchmark' | grep -v gaussian_distribution_gentables | grep -v print_hash_of | grep -v chi_square
// ```
//
fn AddThirdPartyAbseilCppSources(b: *Builder, step: *std.build.LibExeObjStep, options: Options, target: std.Target) void {
    _ = options;
    _ = target;
    const flags = &.{include("third_party/abseil-cpp")};

    // absl
    for ([_][]const u8{
        "third_party/abseil-cpp/absl/strings/match.cc",
        "third_party/abseil-cpp/absl/strings/internal/charconv_bigint.cc",
        "third_party/abseil-cpp/absl/strings/internal/cord_rep_btree_reader.cc",
        "third_party/abseil-cpp/absl/strings/internal/cordz_info.cc",
        "third_party/abseil-cpp/absl/strings/internal/cord_internal.cc",
        "third_party/abseil-cpp/absl/strings/internal/cordz_sample_token.cc",
        "third_party/abseil-cpp/absl/strings/internal/cord_rep_consume.cc",
        "third_party/abseil-cpp/absl/strings/internal/charconv_parse.cc",
        "third_party/abseil-cpp/absl/strings/internal/str_format/arg.cc",
        "third_party/abseil-cpp/absl/strings/internal/str_format/float_conversion.cc",
        "third_party/abseil-cpp/absl/strings/internal/str_format/output.cc",
        "third_party/abseil-cpp/absl/strings/internal/str_format/bind.cc",
        "third_party/abseil-cpp/absl/strings/internal/str_format/parser.cc",
        "third_party/abseil-cpp/absl/strings/internal/str_format/extension.cc",
        "third_party/abseil-cpp/absl/strings/internal/cord_rep_ring.cc",
        "third_party/abseil-cpp/absl/strings/internal/cordz_handle.cc",
        "third_party/abseil-cpp/absl/strings/internal/memutil.cc",
        "third_party/abseil-cpp/absl/strings/internal/ostringstream.cc",
        "third_party/abseil-cpp/absl/strings/internal/pow10_helper.cc",
        "third_party/abseil-cpp/absl/strings/internal/utf8.cc",
        "third_party/abseil-cpp/absl/strings/internal/cordz_functions.cc",
        "third_party/abseil-cpp/absl/strings/internal/cord_rep_btree_navigator.cc",
        "third_party/abseil-cpp/absl/strings/internal/escaping.cc",
        "third_party/abseil-cpp/absl/strings/internal/cord_rep_btree.cc",
        "third_party/abseil-cpp/absl/strings/string_view.cc",
        "third_party/abseil-cpp/absl/strings/str_cat.cc",
        "third_party/abseil-cpp/absl/strings/cord.cc",
        "third_party/abseil-cpp/absl/strings/ascii.cc",
        "third_party/abseil-cpp/absl/strings/numbers.cc",
        "third_party/abseil-cpp/absl/strings/charconv.cc",
        "third_party/abseil-cpp/absl/strings/str_split.cc",
        "third_party/abseil-cpp/absl/strings/substitute.cc",
        "third_party/abseil-cpp/absl/strings/escaping.cc",
        "third_party/abseil-cpp/absl/strings/str_replace.cc",
        "third_party/abseil-cpp/absl/types/bad_any_cast.cc",
        "third_party/abseil-cpp/absl/types/bad_optional_access.cc",
        "third_party/abseil-cpp/absl/types/bad_variant_access.cc",
        "third_party/abseil-cpp/absl/flags/parse.cc",
        "third_party/abseil-cpp/absl/flags/usage.cc",
        "third_party/abseil-cpp/absl/flags/internal/private_handle_accessor.cc",
        "third_party/abseil-cpp/absl/flags/internal/usage.cc",
        "third_party/abseil-cpp/absl/flags/internal/program_name.cc",
        "third_party/abseil-cpp/absl/flags/internal/flag.cc",
        "third_party/abseil-cpp/absl/flags/internal/commandlineflag.cc",
        "third_party/abseil-cpp/absl/flags/reflection.cc",
        "third_party/abseil-cpp/absl/flags/usage_config.cc",
        "third_party/abseil-cpp/absl/flags/flag.cc",
        "third_party/abseil-cpp/absl/flags/marshalling.cc",
        "third_party/abseil-cpp/absl/flags/commandlineflag.cc",
        "third_party/abseil-cpp/absl/synchronization/blocking_counter.cc",
        "third_party/abseil-cpp/absl/synchronization/mutex.cc",
        "third_party/abseil-cpp/absl/synchronization/internal/per_thread_sem.cc",
        "third_party/abseil-cpp/absl/synchronization/internal/create_thread_identity.cc",
        "third_party/abseil-cpp/absl/synchronization/internal/waiter.cc",
        "third_party/abseil-cpp/absl/synchronization/internal/graphcycles.cc",
        "third_party/abseil-cpp/absl/synchronization/barrier.cc",
        "third_party/abseil-cpp/absl/synchronization/notification.cc",
        "third_party/abseil-cpp/absl/hash/internal/low_level_hash.cc",
        "third_party/abseil-cpp/absl/hash/internal/hash.cc",
        "third_party/abseil-cpp/absl/hash/internal/city.cc",
        "third_party/abseil-cpp/absl/debugging/symbolize.cc",
        "third_party/abseil-cpp/absl/debugging/failure_signal_handler.cc",
        "third_party/abseil-cpp/absl/debugging/leak_check_disable.cc",
        "third_party/abseil-cpp/absl/debugging/internal/examine_stack.cc",
        "third_party/abseil-cpp/absl/debugging/internal/vdso_support.cc",
        "third_party/abseil-cpp/absl/debugging/internal/stack_consumption.cc",
        "third_party/abseil-cpp/absl/debugging/internal/address_is_readable.cc",
        "third_party/abseil-cpp/absl/debugging/internal/elf_mem_image.cc",
        "third_party/abseil-cpp/absl/debugging/internal/demangle.cc",
        "third_party/abseil-cpp/absl/debugging/leak_check.cc",
        "third_party/abseil-cpp/absl/debugging/stacktrace.cc",
        "third_party/abseil-cpp/absl/status/status_payload_printer.cc",
        "third_party/abseil-cpp/absl/status/status.cc",
        "third_party/abseil-cpp/absl/status/statusor.cc",
        "third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_format.cc",
        "third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_impl.cc",
        "third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_lookup.cc",
        "third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_info.cc",
        "third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_if.cc",
        "third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_fixed.cc",
        "third_party/abseil-cpp/absl/time/internal/cctz/src/zone_info_source.cc",
        "third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_libc.cc",
        "third_party/abseil-cpp/absl/time/internal/cctz/src/civil_time_detail.cc",
        "third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_posix.cc",
        "third_party/abseil-cpp/absl/time/clock.cc",
        "third_party/abseil-cpp/absl/time/duration.cc",
        "third_party/abseil-cpp/absl/time/civil_time.cc",
        "third_party/abseil-cpp/absl/time/format.cc",
        "third_party/abseil-cpp/absl/time/time.cc",
        "third_party/abseil-cpp/absl/container/internal/raw_hash_set.cc",
        "third_party/abseil-cpp/absl/container/internal/hashtablez_sampler_force_weak_definition.cc",
        "third_party/abseil-cpp/absl/container/internal/hashtablez_sampler.cc",
        "third_party/abseil-cpp/absl/numeric/int128.cc",
        "third_party/abseil-cpp/absl/random/gaussian_distribution.cc",
        "third_party/abseil-cpp/absl/random/discrete_distribution.cc",
        "third_party/abseil-cpp/absl/random/seed_gen_exception.cc",
        "third_party/abseil-cpp/absl/random/internal/seed_material.cc",
        "third_party/abseil-cpp/absl/random/internal/randen_slow.cc",
        "third_party/abseil-cpp/absl/random/internal/randen.cc",
        "third_party/abseil-cpp/absl/random/internal/randen_detect.cc",
        "third_party/abseil-cpp/absl/random/internal/randen_round_keys.cc",
        "third_party/abseil-cpp/absl/random/internal/randen_hwaes.cc",
        "third_party/abseil-cpp/absl/random/internal/pool_urbg.cc",
        "third_party/abseil-cpp/absl/random/seed_sequences.cc",
        "third_party/abseil-cpp/absl/base/internal/spinlock_wait.cc",
        "third_party/abseil-cpp/absl/base/internal/periodic_sampler.cc",
        "third_party/abseil-cpp/absl/base/internal/cycleclock.cc",
        "third_party/abseil-cpp/absl/base/internal/spinlock.cc",
        "third_party/abseil-cpp/absl/base/internal/unscaledcycleclock.cc",
        "third_party/abseil-cpp/absl/base/internal/scoped_set_env.cc",
        "third_party/abseil-cpp/absl/base/internal/sysinfo.cc",
        "third_party/abseil-cpp/absl/base/internal/raw_logging.cc",
        "third_party/abseil-cpp/absl/base/internal/throw_delegate.cc",
        "third_party/abseil-cpp/absl/base/internal/strerror.cc",
        "third_party/abseil-cpp/absl/base/internal/thread_identity.cc",
        "third_party/abseil-cpp/absl/base/internal/exponential_biased.cc",
        "third_party/abseil-cpp/absl/base/internal/low_level_alloc.cc",
        "third_party/abseil-cpp/absl/base/log_severity.cc",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }
}

// Adds dawn wire sources; derived from src/dawn_wire/BUILD.gn
fn addDawnWireSources(b: *Builder, step: *std.build.LibExeObjStep, options: Options, target: std.Target) void {
    _ = options;
    _ = target;
    const flags = &.{};

    // dawn_wire_gen
    for ([_][]const u8{
        "out/Debug/gen/src/dawn_wire/WireCmd_autogen.cpp",
        "out/Debug/gen/src/dawn_wire/client/ApiProcs_autogen.cpp",
        "out/Debug/gen/src/dawn_wire/client/ClientHandlers_autogen.cpp",
        "out/Debug/gen/src/dawn_wire/server/ServerDoers_autogen.cpp",
        "out/Debug/gen/src/dawn_wire/server/ServerHandlers_autogen.cpp",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    // dawn_wire_gen
    for ([_][]const u8{
        "src/dawn_wire/ChunkedCommandHandler.cpp",
        "src/dawn_wire/ChunkedCommandSerializer.cpp",
        "src/dawn_wire/Wire.cpp",
        "src/dawn_wire/WireClient.cpp",
        "src/dawn_wire/WireDeserializeAllocator.cpp",
        "src/dawn_wire/WireServer.cpp",
        "src/dawn_wire/client/Buffer.cpp",
        "src/dawn_wire/client/Client.cpp",
        "src/dawn_wire/client/ClientDoers.cpp",
        "src/dawn_wire/client/ClientInlineMemoryTransferService.cpp",
        "src/dawn_wire/client/Device.cpp",
        "src/dawn_wire/client/Queue.cpp",
        "src/dawn_wire/client/ShaderModule.cpp",
        "src/dawn_wire/server/Server.cpp",
        "src/dawn_wire/server/ServerBuffer.cpp",
        "src/dawn_wire/server/ServerDevice.cpp",
        "src/dawn_wire/server/ServerInlineMemoryTransferService.cpp",
        "src/dawn_wire/server/ServerQueue.cpp",
        "src/dawn_wire/server/ServerShaderModule.cpp",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }
}

// Adds dawn utils sources; derived from src/utils/BUILD.gn
fn addDawnUtilsSources(b: *Builder, step: *std.build.LibExeObjStep, options: Options, target: std.Target) void {
    _ = options;
    _ = target;
    const flags = &.{
        "-DDAWN_ENABLE_BACKEND_METAL",
        //"-DDAWN_ENABLE_BACKEND_NULL",
        include("mach/glfw/upstream/glfw/include"),
        include("src"),
        include("src/include"),
        include("out/Debug/gen/src/include"),
    };

    for ([_][]const u8{
        "src/utils/BackendBinding.cpp",
        "src/utils/NullBinding.cpp",
    }) |path| {
        var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
        step.addCSourceFile(abs_path, flags);
    }

    switch (target.os.tag) {
        .windows => {
            if (options.d3d12) {
                for ([_][]const u8{
                    "src/utils/D3D12Binding.cpp",
                }) |path| {
                    var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
                    step.addCSourceFile(abs_path, flags);
                }
            }
        },
        .macos => {
            if (options.metal) {
                for ([_][]const u8{
                    "src/utils/MetalBinding.mm",
                }) |path| {
                    var abs_path = std.fs.path.join(b.allocator, &.{ thisDir(), "libs/dawn", path }) catch unreachable;
                    step.addCSourceFile(abs_path, flags);
                }
            }
        },
        else => {
            if (options.linux_window_manager == .X11) {
            }
        },
    }

    // if (dawn_enable_opengl) {
    //   sources += [ "OpenGLBinding.cpp" ]
    // }

    // if (dawn_enable_vulkan) {
    //   sources += [ "VulkanBinding.cpp" ]
    // }
}

fn include(comptime rel: []const u8) []const u8 {
    return "-I" ++ thisDir() ++ "/libs/dawn/" ++ rel;
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
