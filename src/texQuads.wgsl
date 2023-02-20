struct Uniform {
    posAngle: vec4<f32>,
    scale: vec2<f32>,
    uvPos: vec2<f32>,
    uvScale: vec2<f32>,
    textureIndex: u32,
};

@group(0) @binding(0) var<uniform> uniforms : array<Uniform, 512>;

struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) fragUv : vec2<f32>,
    @location(1) @interpolate(flat) textureIndex: u32,
};

// Rotates 2D vector "v" around the origin by angle "angle" (in radians).
fn rotateVec2(v: vec2<f32>, angle: f32) -> vec2<f32>
{
    let sinA = sin(angle);
    let cosA = cos(angle);
    return vec2<f32>(v.x * cosA - v.y * sinA, v.y * cosA + v.x * sinA);
}

@vertex
fn vertexMain(
    @builtin(instance_index) instanceIdx : u32,
    @location(0) position : vec3<f32>,
    @location(1) uv : vec2<f32>) -> VertexOutput
{
    let u = uniforms[instanceIdx];
    let scaled = position.xy * u.scale;
    let halfScale = u.scale / 2.0;
    let scaledRotated = rotateVec2(scaled - halfScale, u.posAngle.w) + halfScale;
    let pos = vec3<f32>(scaledRotated, 0) + u.posAngle.xyz;

    var output : VertexOutput;
    output.Position = vec4<f32>(pos, 1);
    output.fragUv = uv * u.uvScale + u.uvPos;
    output.textureIndex = u.textureIndex;
    return output;
}

@group(0) @binding(1) var mySampler: sampler;
@group(0) @binding(2) var texture1: texture_2d<f32>;
@group(0) @binding(3) var texture2: texture_2d<f32>;

@fragment
fn fragMain(@location(0) fragUv: vec2<f32>, @location(1) @interpolate(flat) textureIndex: u32) -> @location(0) vec4<f32>
{
    var color : vec4<f32>;
    switch (textureIndex) {
        case 0: {
            color = textureSample(texture1, mySampler, fragUv);
        }
        case 1: {
            color = textureSample(texture2, mySampler, fragUv);
        }
        default: {
            color = vec4<f32>(1.0, 0.0, 1.0, 1.0);
        }
    }
    return color;
}
