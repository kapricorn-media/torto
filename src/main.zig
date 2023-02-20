const std = @import("std");

const mach = @import("mach");
const gpu = @import("gpu");
const glfw = @import("glfw");
const zm = @import("zmath");
const zigimg = @import("zigimg");

const input = @import("input.zig");
const render = @import("render.zig");
const torto = @import("torto.zig");
const vertices = @import("vertices.zig");
const Vertex = vertices.Vertex;
const assets = @import("assets");

pub const Texture = enum(u8) {
    Zig = 0,
    Torto,
};

pub const App = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

core: mach.Core,
timer: mach.Timer,
fpsTimer: mach.Timer,
windowTitleTimer: mach.Timer,
pipeline: *gpu.RenderPipeline,
queue: *gpu.Queue,
vertexBuffer: *gpu.Buffer,
uniformBuffer: *gpu.Buffer,
bindGroup: *gpu.BindGroup,
depthTexture: *gpu.Texture,
depthTextureView: *gpu.TextureView,

transientMemory: []u8,
assets: render.Assets(Texture),
inputState: input.InputState,
prevTime: f32,
tortoState: torto.State,

fn getTransientAllocator(app: *App) std.heap.FixedBufferAllocator
{
    return std.heap.FixedBufferAllocator.init(app.transientMemory);
}

pub fn init(app: *App) !void
{
    const allocator = gpa.allocator();
    try app.core.init(allocator, .{
        .size = .{ .width = 1280, .height = 800 },
    });

    app.transientMemory = try allocator.alloc(u8, 1024 * 1024 * 1024);
    var transientAllocator = app.getTransientAllocator();
    const tempAllocator = transientAllocator.allocator();

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

    try app.assets.loadTexture(Texture.Zig, assets.zigPng, app.core.device(), tempAllocator);
    try app.assets.loadTexture(Texture.Torto, assets.tortoPng, app.core.device(), tempAllocator);

    // Create a sampler with linear filtering for smooth interpolation.
    const sampler = app.core.device().createSampler(&.{
        .mag_filter = .linear,
        .min_filter = .linear,
    });

    const uniformBuffer = app.core.device().createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(render.UniformData) * render.MAX_INSTANCES,
        .mapped_at_creation = false,
    });

    // TODO inline-for this thingy and the binding generation
    const zigTexture = app.assets.getTexture(Texture.Zig) orelse return error.NoZig;
    const tortoTexture = app.assets.getTexture(Texture.Torto) orelse return error.NoTorto;

    const bindGroup = app.core.device().createBindGroup(
        &gpu.BindGroup.Descriptor.init(.{
            .layout = pipeline.getBindGroupLayout(0),
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, uniformBuffer, 0, @sizeOf(render.UniformData) * render.MAX_INSTANCES),
                gpu.BindGroup.Entry.sampler(1, sampler),
                // NOTE: This must match the Texture enum order!
                gpu.BindGroup.Entry.textureView(
                    2, zigTexture.texture.createView(&gpu.TextureView.Descriptor{})
                ),
                gpu.BindGroup.Entry.textureView(
                    3, tortoTexture.texture.createView(&gpu.TextureView.Descriptor{})
                ),
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
    app.fpsTimer = try mach.Timer.start();
    app.windowTitleTimer = try mach.Timer.start();
    app.pipeline = pipeline;
    app.queue = app.core.device().getQueue();
    app.vertexBuffer = vertexBuffer;
    app.uniformBuffer = uniformBuffer;
    app.bindGroup = bindGroup;
    app.depthTexture = depthTexture;
    app.depthTextureView = depthTextureView;

    try app.assets.init();
    app.inputState.init();
    app.tortoState.init();

    shaderModule.release();
}

pub fn deinit(app: *App) void
{
    defer {
        const allocator = gpa.allocator();
        allocator.free(app.transientMemory);
        app.core.deinit();
        _ = gpa.deinit();
    }

    app.vertexBuffer.release();
    app.uniformBuffer.release();
    app.bindGroup.release();
    app.depthTexture.release();
    app.depthTextureView.release();
}

pub fn update(app: *App) !bool
{
    var transientAllocator = app.getTransientAllocator();
    const tempAllocator = transientAllocator.allocator();

    var iter = app.core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                const vsyncPrev = app.core.vsync();
                switch (ev.key) {
                    .space => return true,
                    .one => app.core.setVSync(.none),
                    .two => app.core.setVSync(.double),
                    .three => app.core.setVSync(.triple),
                    else => {},
                }
                const vsyncNew = app.core.vsync();
                if (vsyncNew != vsyncPrev) {
                    std.log.info("vsync mode changed to {s}", .{@tagName(app.core.vsync())});
                }
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

        try app.inputState.addEvent(event);
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

    var renderState: render.RenderState = undefined;
    try renderState.init(tempAllocator);

    const time = app.timer.read();
    const deltaTime = time - app.prevTime;
    try torto.update(app, deltaTime, &renderState);
    app.prevTime = time;

    renderState.pushToUniformBuffer(encoder, app.uniformBuffer);

    const pass = encoder.beginRenderPass(&renderPassInfo);
    pass.setPipeline(app.pipeline);
    pass.setVertexBuffer(0, app.vertexBuffer, 0, @sizeOf(vertices.Vertex) * vertices.quad.len);
    pass.setBindGroup(0, app.bindGroup, &.{});
    pass.draw(vertices.quad.len, renderState.n, 0, 0);
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    app.queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    app.core.swapChain().present();
    backBufferView.release();

    const fpsDeltaTime = app.fpsTimer.lap();
    if (app.windowTitleTimer.read() >= 1.0) {
        app.windowTitleTimer.reset();
        const title = try std.fmt.allocPrintZ(tempAllocator, "Torto [ FPS: {d} ]", .{@floor(1 / fpsDeltaTime)});
        app.core.setTitle(title);
    }

    return false;
}
