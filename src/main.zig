const std = @import("std");

const mach = @import("mach");
const gpu = @import("gpu");
const glfw = @import("glfw");
const zm = @import("zmath");
const zigimg = @import("zigimg");

const vertices = @import("vertices.zig");
const Vertex = vertices.Vertex;
const assets = @import("assets");

pub const App = @This();

const UniformData = struct {
    pos: @Vector(3, f32),
    scale: @Vector(2, f32),
    uvPos: @Vector(2, f32),
    uvScale: @Vector(2, f32),
};

const Texture = enum(u8) {
    Zig = 0,
    Torto,
};

const TextureData = struct {
};

fn Assets(comptime TextureEnum: type) type
{
    const T = struct {
        const numTextures = @typeInfo(TextureEnum).Enum.fields.len;
        textures: [numTextures]TextureData,

        const Self = @This();

        fn init(self: *Self) !void
        {
            _ = self;
        }
    };
    return T;
}

const MAX_INSTANCES = 512;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

core: mach.Core,
timer: mach.Timer,
fps_timer: mach.Timer,
window_title_timer: mach.Timer,
pipeline: *gpu.RenderPipeline,
queue: *gpu.Queue,
vertexBuffer: *gpu.Buffer,
uniformBuffer: *gpu.Buffer,
bindGroup: *gpu.BindGroup,
depthTexture: *gpu.Texture,
depthTextureView: *gpu.TextureView,

assets: Assets(Texture),

pub fn init(app: *App) !void
{
    const allocator = gpa.allocator();
    try app.core.init(allocator, .{});

    const shaderModule = app.core.device().createShaderModuleWGSL("texQuads.wgsl", @embedFile("texQuads.wgsl"));

    const vertexAttributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x3, .offset = @offsetOf(vertices.Vertex, "pos"), .shader_location = 0 },
        .{ .format = .float32x2, .offset = @offsetOf(vertices.Vertex, "uv"), .shader_location = 1 },
    };
    const vertexBufferLayout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(vertices.Vertex),
        .step_mode = .vertex,
        .attributes = &vertexAttributes,
    });

    const blend = gpu.BlendState{
        .color = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
        .alpha = .{
            .operation = .add,
            .src_factor = .one,
            .dst_factor = .zero,
        },
    };
    const colorTarget = gpu.ColorTargetState{
        .format = app.core.descriptor().format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = gpu.FragmentState.init(.{
        .module = shaderModule,
        .entry_point = "fragMain",
        .targets = &.{colorTarget},
    });

    const pipelineDescriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        // Enable depth testing so that the fragment closest to the camera
        // is rendered in front.
        .depth_stencil = &.{
            .format = .depth24_plus,
            .depth_write_enabled = true,
            .depth_compare = .less,
        },
        .vertex = gpu.VertexState.init(.{
            .module = shaderModule,
            .entry_point = "vertexMain",
            .buffers = &.{vertexBufferLayout},
        }),
        .primitive = .{
            // Backface culling since the cube is solid piece of geometry.
            // Faces pointing away from the camera will be occluded by faces
            // pointing toward the camera.
            .cull_mode = .back,
        },
    };
    const pipeline = app.core.device().createRenderPipeline(&pipelineDescriptor);

    const vertexBuffer = app.core.device().createBuffer(&.{
        .usage = .{ .vertex = true },
        .size = @sizeOf(vertices.Vertex) * vertices.quad.len,
        .mapped_at_creation = true,
    });
    var vertexMapped = vertexBuffer.getMappedRange(vertices.Vertex, 0, vertices.quad.len);
    std.mem.copy(vertices.Vertex, vertexMapped.?, vertices.quad[0..]);
    vertexBuffer.unmap();

    // Create a sampler with linear filtering for smooth interpolation.
    const sampler = app.core.device().createSampler(&.{
        .mag_filter = .linear,
        .min_filter = .linear,
    });
    const queue = app.core.device().getQueue();
    var img = try zigimg.Image.fromMemory(allocator, assets.gotta_go_fast_image);
    defer img.deinit();
    const img_size = gpu.Extent3D{ .width = @intCast(u32, img.width), .height = @intCast(u32, img.height) };
    const texture1 = app.core.device().createTexture(&.{
        .size = img_size,
        .format = .rgba8_unorm,
        .usage = .{
            .texture_binding = true,
            .copy_dst = true,
            .render_attachment = true,
        },
    });
    const dataLayout = gpu.Texture.DataLayout{
        .bytes_per_row = @intCast(u32, img.width * 4),
        .rows_per_image = @intCast(u32, img.height),
    };
    switch (img.pixels) {
        .rgba32 => |pixels| queue.writeTexture(&.{ .texture = texture1 }, &dataLayout, &img_size, pixels),
        .rgb24 => |pixels| {
            const data = try rgb24ToRgba32(allocator, pixels);
            defer data.deinit(allocator);
            queue.writeTexture(&.{ .texture = texture1 }, &dataLayout, &img_size, data.rgba32);
        },
        else => @panic("unsupported image color format"),
    }

    const uniformBuffer = app.core.device().createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(UniformData) * MAX_INSTANCES,
        .mapped_at_creation = false,
    });

    const bindGroup = app.core.device().createBindGroup(
        &gpu.BindGroup.Descriptor.init(.{
            .layout = pipeline.getBindGroupLayout(0),
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, uniformBuffer, 0, @sizeOf(UniformData) * MAX_INSTANCES),
                gpu.BindGroup.Entry.sampler(1, sampler),
                gpu.BindGroup.Entry.textureView(2, texture1.createView(&gpu.TextureView.Descriptor{})),
            },
        }),
    );

    const depthTexture = app.core.device().createTexture(&gpu.Texture.Descriptor{
        .size = gpu.Extent3D{
            .width = app.core.descriptor().width,
            .height = app.core.descriptor().height,
        },
        .format = .depth24_plus,
        .usage = .{
            .render_attachment = true,
            .texture_binding = true,
        },
    });

    const depthTextureView = depthTexture.createView(&gpu.TextureView.Descriptor{
        .format = .depth24_plus,
        .dimension = .dimension_2d,
        .array_layer_count = 1,
        .mip_level_count = 1,
    });

    app.timer = try mach.Timer.start();
    app.fps_timer = try mach.Timer.start();
    app.window_title_timer = try mach.Timer.start();
    app.pipeline = pipeline;
    app.queue = queue;
    app.vertexBuffer = vertexBuffer;
    app.uniformBuffer = uniformBuffer;
    app.bindGroup = bindGroup;
    app.depthTexture = depthTexture;
    app.depthTextureView = depthTextureView;

    try app.assets.init();

    shaderModule.release();
}

pub fn deinit(app: *App) void
{
    defer _ = gpa.deinit();
    defer app.core.deinit();

    app.vertexBuffer.release();
    app.uniformBuffer.release();
    app.bindGroup.release();
    app.depthTexture.release();
    app.depthTextureView.release();
}

pub fn update(app: *App) !bool
{
    var iter = app.core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                switch (ev.key) {
                    .space => return true,
                    .one => app.core.setVSync(.none),
                    .two => app.core.setVSync(.double),
                    .three => app.core.setVSync(.triple),
                    else => {},
                }
                std.debug.print("vsync mode changed to {s}\n", .{@tagName(app.core.vsync())});
            },
            .framebuffer_resize => |ev| {
                // If window is resized, recreate depth buffer otherwise we cannot use it.
                app.depthTexture.release();

                app.depthTexture = app.core.device().createTexture(&gpu.Texture.Descriptor{
                    .size = gpu.Extent3D{
                        .width = ev.width,
                        .height = ev.height,
                    },
                    .format = .depth24_plus,
                    .usage = .{
                        .render_attachment = true,
                        .texture_binding = true,
                    },
                });

                app.depthTextureView.release();
                app.depthTextureView = app.depthTexture.createView(&gpu.TextureView.Descriptor{
                    .format = .depth24_plus,
                    .dimension = .dimension_2d,
                    .array_layer_count = 1,
                    .mip_level_count = 1,
                });
            },
            .close => return true,
            else => {},
        }
    }

    const backBufferView = app.core.swapChain().getCurrentTextureView();
    const colorAttachment = gpu.RenderPassColorAttachment{
        .view = backBufferView,
        .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 },
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = app.core.device().createCommandEncoder(null);
    const renderPassInfo = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{colorAttachment},
        .depth_stencil_attachment = &.{
            .view = app.depthTextureView,
            .depth_clear_value = 1.0,
            .depth_load_op = .clear,
            .depth_store_op = .store,
        },
    });

    {
        const time = app.timer.read();
        const period = 1.0;
        const modTime = std.math.modf(time / period);
        const t = modTime.fpart;
        var uniforms: [4]UniformData = undefined;
        uniforms[0] = UniformData{
            .pos = .{ t * 0.5, t * 0.25, 0 },
            .scale = .{ 1, 1 },
            .uvPos = .{ 0, 0 },
            .uvScale = .{ 1 - t * 0.2, 1 - t * 0.4 },
        };
        uniforms[1] = UniformData{
            .pos = .{ -0.5, -0.5, 0 },
            .scale = .{ 0.2, 0.2 },
            .uvPos = .{ 0, 0 },
            .uvScale = .{ 1 + t, 1 - t },
        };
        encoder.writeBuffer(app.uniformBuffer, 0, &uniforms);
    }

    const pass = encoder.beginRenderPass(&renderPassInfo);
    pass.setPipeline(app.pipeline);
    pass.setVertexBuffer(0, app.vertexBuffer, 0, @sizeOf(vertices.Vertex) * vertices.quad.len);
    pass.setBindGroup(0, app.bindGroup, &.{});
    pass.draw(vertices.quad.len, 2, 0, 0);
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    app.queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    app.core.swapChain().present();
    backBufferView.release();

    const delta_time = app.fps_timer.lap();
    if (app.window_title_timer.read() >= 1.0) {
        app.window_title_timer.reset();
        var buf: [32]u8 = undefined;
        const title = try std.fmt.bufPrintZ(&buf, "Torto [ FPS: {d} ]", .{@floor(1 / delta_time)});
        app.core.setTitle(title);
    }

    return false;
}

fn rgb24ToRgba32(allocator: std.mem.Allocator, in: []zigimg.color.Rgb24) !zigimg.color.PixelStorage {
    const out = try zigimg.color.PixelStorage.init(allocator, .rgba32, in.len);
    var i: usize = 0;
    while (i < in.len) : (i += 1) {
        out.rgba32[i] = zigimg.color.Rgba32{ .r = in[i].r, .g = in[i].g, .b = in[i].b, .a = 255 };
    }
    return out;
}
