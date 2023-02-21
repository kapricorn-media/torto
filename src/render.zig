const std = @import("std");

const gpu = @import("gpu");
const zigimg = @import("zigimg");

pub const InstanceData = extern struct {
    posAngle: @Vector(4, f32),
    size: @Vector(2, f32),
    uvPos: @Vector(2, f32),
    uvSize: @Vector(2, f32),
    textureIndex: u32,
};

pub const UniformData = extern struct {
    // max number of quad texture instances in 1 draw call
    pub const MAX_INSTANCES = 512;

    instances: [MAX_INSTANCES]InstanceData,
    screenSize: @Vector(2, f32),
};

const TextureData = struct {
    texture: *gpu.Texture,
};

fn rgb24ToRgba32(allocator: std.mem.Allocator, in: []zigimg.color.Rgb24) !zigimg.color.PixelStorage {
    const out = try zigimg.color.PixelStorage.init(allocator, .rgba32, in.len);
    var i: usize = 0;
    while (i < in.len) : (i += 1) {
        out.rgba32[i] = zigimg.color.Rgba32{ .r = in[i].r, .g = in[i].g, .b = in[i].b, .a = 255 };
    }
    return out;
}

fn rgba32FlipY(width: usize, height: usize, rgba32: []zigimg.color.Rgba32) void
{
    var y: usize = 0;
    const halfHeight = height / 2 - 1;
    while (y < halfHeight) : (y += 1) {
        const yOpposite = height - y - 1;
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const temp = rgba32[y * width + x];
            rgba32[y * width + x] = rgba32[yOpposite * width + x];
            rgba32[yOpposite * width + x] = temp;
        }
    }
}

pub fn Assets(comptime TextureEnum: type) type
{
    const T = struct {
        const numTextures = @typeInfo(TextureEnum).Enum.fields.len;
        textures: [numTextures]TextureData,

        const Self = @This();

        pub fn init(self: *Self) !void
        {
            _ = self;
        }

        pub fn loadTexture(self: *Self, texture: TextureEnum, pngData: []const u8, device: *gpu.Device,  allocator: std.mem.Allocator) !void
        {
            var img = try zigimg.Image.fromMemory(allocator, pngData);
            defer img.deinit();
            const imgSize = gpu.Extent3D{
                .width = @intCast(u32, img.width),
                .height = @intCast(u32, img.height)
            };
            const tex = device.createTexture(&.{
                .size = imgSize,
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
            const queue = device.getQueue();
            // TODO free if necessary
            const dataRgba32 = blk: {
                switch (img.pixels) {
                    .rgba32 => |pixels| break :blk pixels,
                    .rgb24 => |pixels| break :blk (try rgb24ToRgba32(allocator, pixels)).rgba32,
                    else => {
                        std.log.err("Invalid image pixel format {s}", .{std.meta.tagName(img.pixels)});
                        return error.UnsupportedImage;
                    },
                }
            };
            rgba32FlipY(img.width, img.height, dataRgba32);
            queue.writeTexture(&.{ .texture = tex }, &dataLayout, &imgSize, dataRgba32);

            self.textures[@enumToInt(texture)] = .{
                .texture = tex,
            };
        }

        pub fn getTexture(self: *const Self, texture: TextureEnum) ?TextureData
        {
            return self.textures[@enumToInt(texture)];
        }
    };
    return T;
}

pub const RenderState = struct {
    n: u32,
    uniformData: UniformData,

    const Self = @This();

    pub fn init(self: *Self) void
    {
        self.n = 0;
    }

    pub fn drawTexturedQuad(
        self: *Self,
        pos: @Vector(2, f32),
        depth: f32,
        angle: f32,
        size: @Vector(2, f32),
        texture: anytype) !void
    {
        if (self.n >= UniformData.MAX_INSTANCES) {
            return error.Full;
        }
        self.uniformData.instances[self.n] = .{
            .posAngle = .{pos[0], pos[1], depth, angle},
            .size = size,
            .uvPos = .{0, 0},
            .uvSize = .{1, 1},
            .textureIndex = @enumToInt(texture),
        };
        self.n += 1;
    }

    pub fn pushToUniformBuffer(self: *Self, screenSize: @Vector(2, f32), encoder: *gpu.CommandEncoder, uniformBuffer: *gpu.Buffer) void
    {
        self.uniformData.screenSize = screenSize;
        encoder.writeBuffer(uniformBuffer, 0, std.mem.asBytes(&self.uniformData));
    }
};
