struct InstanceData {
    posAngle: vec4<f32>,
    size: vec2<f32>,
    uvPos: vec2<f32>,
    uvSize: vec2<f32>,
    textureIndex: u32,
};

struct UniformData {
    instances: array<InstanceData, 512>,
    screenSize: vec2<f32>,
};

@group(0) @binding(0) var<uniform> uniformData : UniformData;

struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) fragUv : vec2<f32>,
    @location(1) @interpolate(flat) textureIndex: u32,
};

fn pixelPosToNdc(v: vec2<f32>, screenSize: vec2<f32>) -> vec2<f32>
{
    return v / screenSize * 2.0 - 1.0;
}

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
    let instanceData = uniformData.instances[instanceIdx];
    let scaled = position.xy * instanceData.size;
    let halfScale = instanceData.size / 2.0;
    let scaledRotated = rotateVec2(scaled - halfScale, instanceData.posAngle.w) + halfScale;
    let posNdc = pixelPosToNdc(scaledRotated + instanceData.posAngle.xy, uniformData.screenSize);
    let posNdc3 = vec3<f32>(posNdc, instanceData.posAngle.z);

    var output : VertexOutput;
    output.Position = vec4<f32>(posNdc3, 1);
    output.fragUv = uv * instanceData.uvSize + instanceData.uvPos;
    output.textureIndex = instanceData.textureIndex;
    return output;
}

@group(0) @binding(1) var mySampler: sampler;
@group(0) @binding(2) var texture1: texture_2d<f32>;
@group(0) @binding(3) var texture2: texture_2d<f32>;
@group(0) @binding(4) var texture3: texture_2d<f32>;

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
        case 2: {
            color = textureSample(texture3, mySampler, fragUv);
        }
        default: {
            color = vec4<f32>(1.0, 0.0, 1.0, 1.0);
        }
    }
    return color;
}
