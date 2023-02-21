const std = @import("std");

const App = @import("main.zig").App;
const Texture = @import("main.zig").Texture;
const render = @import("render.zig");

pub const State = struct {
    x: f32,
    y: f32,
    angle: f32,

    // Set initial values
    pub fn init(state: *State) void
    {
        state.* = .{
            .x = 0,
            .y = 0,
            .angle = 0,
        };
    }
};

pub fn update(app: *App, deltaTime: f32, renderState: *render.RenderState) !void
{
    var state = &app.tortoState;
    const input = &app.inputState;
    const windowSize = app.core.size();
    const windowSizeF: @Vector(2, f32) = .{
        @intToFloat(f32, windowSize.width), @intToFloat(f32, windowSize.height)
    };

    // Object depths are in the range [0.0, 1.0), where objects with smaller depth numbers are "on top".
    const depthBackground = 0.80;
    const depthTorti = 0.50;

    // Draw background first
    // TODO pixel size should be adjusted to the background's aspect ratio. Image will stretch as is.
    try renderState.drawTexturedQuad(.{0, 0}, depthBackground, 0.0, windowSizeF, Texture.Background);

    const speed = 500.0;
    if (input.keyPressed(.a) or input.keyPressed(.left)) {
        state.x -= speed * deltaTime;
    }
    if (input.keyPressed(.d) or input.keyPressed(.right)) {
        state.x += speed * deltaTime;
    }
    if (input.keyPressed(.s) or input.keyPressed(.down)) {
        state.y -= speed * deltaTime;
    }
    if (input.keyPressed(.w) or input.keyPressed(.up)) {
        state.y += speed * deltaTime;
    }

    if (input.keyPressed(.q)) {
        state.angle += std.math.pi * deltaTime;
    }
    if (input.keyPressed(.e)) {
        state.angle -= std.math.pi * deltaTime;
    }

    const tortiPixelSize = @Vector(2, f32) {
        300, 150
    };
    try renderState.drawTexturedQuad(
        .{state.x, state.y},
        depthTorti,
        state.angle,
        tortiPixelSize,
        Texture.Torto
    );
}
