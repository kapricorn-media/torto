pub const Vertex = extern struct {
    pos: @Vector(3, f32),
    uv: @Vector(2, f32),
};

pub const quad = [_]Vertex{
    .{ .pos = .{ 0, 0, 0 }, .uv = .{ 0, 0 } },
    .{ .pos = .{ 1, 0, 0 }, .uv = .{ 1, 0 } },
    .{ .pos = .{ 1, 1, 0 }, .uv = .{ 1, 1 } },
    .{ .pos = .{ 1, 1, 0 }, .uv = .{ 1, 1 } },
    .{ .pos = .{ 0, 1, 0 }, .uv = .{ 0, 1 } },
    .{ .pos = .{ 0, 0, 0 }, .uv = .{ 0, 0 } },
};
