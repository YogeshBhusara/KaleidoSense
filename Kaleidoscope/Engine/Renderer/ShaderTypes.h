//
//  ShaderTypes.h
//  KaleidoSense
//
//  Shared memory layout between Swift (host) and Metal (device).
//  This file is used both as the Objective-C bridging header for the Swift
//  target and is `#include`d by the Metal shader, guaranteeing that the
//  `Uniforms` and `GPUParticle` structs have identical byte layouts on both
//  sides. Always mutate them here in a single place.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// Maximum number of glass fragments uploaded to the GPU per frame.
// Kept intentionally small so the per-pixel particle loop in the fragment
// shader stays inside the 120 FPS budget even on non-Pro devices.
#define KS_MAX_PARTICLES 64

// Indices used to bind buffers in the fragment shader.
typedef enum KSBufferIndex {
    KSBufferIndexUniforms  = 0,
    KSBufferIndexParticles = 1
} KSBufferIndex;

// A single colored glass fragment, already folded into the base symmetry
// wedge on the CPU so the fragment shader only performs cheap distance math.
typedef struct {
    vector_float2 position;   // folded position in pattern space (~[-1.4, 1.4])
    vector_float4 color;      // premultiplied-ish rgba glass color
    float radius;             // soft core radius
    float rotation;           // facet orientation (radians)
    float refraction;         // 0...1 shimmer / refraction strength
    float seed;               // per-particle random phase
} GPUParticle;

// Per-frame render parameters. 16-byte aligned vectors are grouped first to
// keep the layout deterministic across the Swift / Metal boundary.
typedef struct {
    vector_float4 paletteA;          // primary glass tint
    vector_float4 paletteB;          // secondary glass tint
    vector_float4 paletteC;          // accent tint
    vector_float4 background;        // chamber background color

    vector_float2 resolution;        // drawable size in pixels
    vector_float2 tilt;              // roll / pitch driven translation

    float time;                      // seconds since start
    float segments;                  // symmetry segment count (e.g. 6/8/12/16)
    float rotationZ;                 // accumulated yaw rotation (radians)
    float motionEnergy;              // 0...1 overall movement magnitude

    float zoom;                      // pattern zoom factor
    float patternRotation;           // idle drift rotation (radians)
    int   particleCount;             // active particles in buffer
    int   mode;                      // KaleidoscopeMode raw value

    float bloom;                     // bloom / halo intensity
    float chromaticAberration;       // subtle RGB split
    float lensDistortion;            // barrel distortion amount
    float glow;                      // additive glow

    float refraction;                // global refraction multiplier
    float reduceMotion;              // 1 when Reduce Motion is enabled
    float reduceTransparency;        // 1 when Reduce Transparency is enabled
    float vignette;                  // vignette strength
} Uniforms;

#endif /* ShaderTypes_h */
