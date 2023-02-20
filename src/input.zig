const std = @import("std");

const mach = @import("mach");

pub const InputState = @This();

const KeyState = struct {
    pressed: bool,
};

state: [@typeInfo(mach.Core.Key).Enum.fields.len]KeyState,

pub fn init(inputState: *InputState) void
{
    for (inputState.state) |*s| {
        s.pressed = false;
    }
}

pub fn addEvent(inputState: *InputState, event: mach.Core.Event) !void
{
    switch (event) {
        .key_press => |ev| {
            const index = @enumToInt(ev.key);
            inputState.state[index].pressed = true;
        },
        .key_repeat => |ev| {
            const index = @enumToInt(ev.key);
            inputState.state[index].pressed = true;
        },
        .key_release => |ev| {
            const index = @enumToInt(ev.key);
            inputState.state[index].pressed = false;
        },
        else => {},
    }
}

pub fn keyPressed(inputState: *const InputState, k: mach.Core.Key) bool
{
    const index = @enumToInt(k);
    return inputState.state[index].pressed;
}
