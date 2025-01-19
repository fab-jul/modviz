#include <metal_stdlib>
using namespace metal;

//vertex float4 vertex_shader(constant float4 *vertices [[buffer(0)]],
//                           uint vid [[vertex_id]]) {
//    return vertices[vid];
//}

// Uniform data structure (must match the Swift struct)
struct UniformData {
    float rotation;
    float3 color; // Use float3 for SIMD3<Float>
};

fragment float4 fragment_shader(constant UniformData &uniforms [[buffer(1)]]) {
    // Use the color from the uniforms
    return float4(uniforms.color, 1.0);
}


vertex float4 vertex_shader(constant float4 *vertices [[buffer(0)]],
                           constant UniformData &uniforms [[buffer(1)]],
                           uint vid [[vertex_id]]) {
    float angle = uniforms.rotation;

    // 2D rotation matrix
    float2x2 rotationMatrix = float2x2(cos(angle), -sin(angle),
                                     sin(angle),  cos(angle));

    // Fetch the vertex position from the vertices array
    float4 inPosition = vertices[vid];

    // Apply rotation to the position
    float4 rotatedPosition = float4(rotationMatrix * inPosition.xy, inPosition.zw);

    return rotatedPosition;
}
