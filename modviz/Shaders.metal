#include <metal_stdlib>
using namespace metal;

//vertex float4 vertex_shader(constant float4 *vertices [[buffer(0)]],
//                           uint vid [[vertex_id]]) {
//    return vertices[vid];
//}

fragment float4 fragment_shader() {
    return float4(1.0, 0.0, 0.0, 1.0); // Red color
}


// Structure to hold uniform data (like rotation)
struct Uniforms {
    float rotation;
};

vertex float4 vertex_shader(constant float4 *vertices [[buffer(0)]],
                           constant Uniforms &uniforms [[buffer(1)]],
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
