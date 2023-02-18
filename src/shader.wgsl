struct Uniform {
    pos: vec3<f32>,
    scale: vec2<f32>,
    uvPos: vec2<f32>,
    uvScale: vec2<f32>,
};

@binding(0) @group(0) var<uniform> uniforms : array<Uniform, 1>;

struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) fragUV : vec2<f32>,
};

@vertex
fn vertex_main(@location(0) position : vec3<f32>, @location(1) uv : vec2<f32>) -> VertexOutput
{
    var output : VertexOutput;
    var pos: vec3<f32> = vec3<f32>(position.xy * uniforms[0].scale, position.z) + uniforms[0].pos;
    output.Position = vec4<f32>(pos, 1);
    output.fragUV = uv * uniforms[0].uvScale + uniforms[0].uvPos;
    return output;
}

@group(0) @binding(1) var mySampler: sampler;
@group(0) @binding(2) var myTexture: texture_2d<f32>;

@fragment
fn frag_main(@location(0) fragUV: vec2<f32>) -> @location(0) vec4<f32>
{
    return textureSample(myTexture, mySampler, fragUV);
}
