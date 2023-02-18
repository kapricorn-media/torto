struct Uniform {
    pos: vec3<f32>,
    scale: vec2<f32>,
    uvPos: vec2<f32>,
    uvScale: vec2<f32>,
};

@group(0) @binding(0) var<uniform> uniforms : array<Uniform, 512>;

struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) fragUV : vec2<f32>,
};

@vertex
fn vertexMain(
    @builtin(instance_index) instanceIdx : u32,
    @location(0) position : vec3<f32>,
    @location(1) uv : vec2<f32>) -> VertexOutput
{
    var u = uniforms[instanceIdx];
    var output : VertexOutput;
    var pos: vec3<f32> = vec3<f32>(position.xy * u.scale, position.z) + u.pos;
    output.Position = vec4<f32>(pos, 1);
    output.fragUV = uv * u.uvScale + u.uvPos;
    return output;
}

@group(0) @binding(1) var mySampler: sampler;
@group(0) @binding(2) var myTexture: texture_2d<f32>;

@fragment
fn fragMain(@location(0) fragUV: vec2<f32>) -> @location(0) vec4<f32>
{
    return textureSample(myTexture, mySampler, fragUV);
}
