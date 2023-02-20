const std = @import("std");

const App = @import("main.zig").App;
const Texture = @import("main.zig").Texture;
const render = @import("render.zig");

pub const State = struct {
    x: f32,
    y: f32,

    // Set initial values
    pub fn init(state: *State) void
    {
        state.x = 0;
        state.y = 0;
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

    try renderState.drawTexturedQuad(
        .{state.x, state.y},
        0,
        .{300, 150},
        Texture.Torto,
        windowSizeF
    );
}
