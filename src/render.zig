const std = @import("std");

const gpu = @import("gpu");
const zigimg = @import("zigimg");

// max number of quad texture instances in 1 draw call
pub const MAX_INSTANCES = 512;

pub const UniformData = struct {
    pos: @Vector(3, f32),
    scale: @Vector(2, f32),
    uvPos: @Vector(2, f32),
    uvScale: @Vector(2, f32),
    textureIndex: u32,
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
                    else => @panic("unsupported image color format"),
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
    texturedQuads: []UniformData,

    const Self = @This();

    pub fn init(self: *Self, allocator: std.mem.Allocator) !void
    {
        self.n = 0;
        self.texturedQuads = try allocator.alloc(UniformData, MAX_INSTANCES);
    }

    pub fn drawTexturedQuadNdc(
        self: *Self,
        pos: @Vector(3, f32),
        scale: @Vector(2, f32),
        uvPos: @Vector(2, f32),
        uvScale: @Vector(2, f32),
        texture: anytype) !void
    {
        if (self.n >= MAX_INSTANCES) {
            return error.Full;
        }
        self.texturedQuads[self.n] = UniformData {
            .pos = pos,
            .scale = scale,
            .uvPos = uvPos,
            .uvScale = uvScale,
            .textureIndex = @enumToInt(texture),
        };
        self.n += 1;
    }

    pub fn drawTexturedQuad(
        self: *Self,
        pos: @Vector(2, f32),
        depth: f32,
        scale: @Vector(2, f32),
        texture: anytype,
        screenSize: @Vector(2, f32)) !void
    {
        const posNdc = pixelPosToNdc(pos, screenSize);
        try self.drawTexturedQuadNdc(
            .{posNdc[0], posNdc[1], depth},
            pixelSizeToNdc(scale, screenSize),
            .{0, 0},
            .{1, 1},
            texture
        );
    }

    pub fn pushToUniformBuffer(self: *const Self, encoder: *gpu.CommandEncoder, uniformBuffer: *gpu.Buffer) void
    {
        encoder.writeBuffer(uniformBuffer, 0, self.texturedQuads);
    }
};

fn pixelPosToNdc(pos: @Vector(2, f32), screenSize: @Vector(2, f32)) @Vector(2, f32)
{
    return pos / screenSize * @Vector(2, f32) {2, 2} - @Vector(2, f32) {1, 1};
}

fn pixelSizeToNdc(size: @Vector(2, f32), screenSize: @Vector(2, f32)) @Vector(2, f32)
{
    return size / screenSize * @Vector(2, f32) {2, 2};
}
