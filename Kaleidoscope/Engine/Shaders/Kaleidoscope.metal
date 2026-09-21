//
//  Kaleidoscope.metal
//  KaleidoSense
//
//  GPU kaleidoscope renderer. A single full-screen fragment pass performs:
//    1. Subtle lens distortion of the screen coordinate.
//    2. Motion-driven rotation and translation of the sampling point.
//    3. Dihedral (mirror + radial) symmetry folding into a base wedge.
//    4. Polygonal cut-glass Voronoi shards with metallic cames.
//    5. Edge-only chromatic aberration, bloom, glow, vignette and ACES tone map.
//

#include <metal_stdlib>
#include "../Renderer/ShaderTypes.h"

using namespace metal;

// MARK: - Vertex stage (full-screen triangle, no vertex buffer needed)

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

vertex VSOut vertex_main(uint vid [[vertex_id]]) {
    const float2 verts[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    VSOut out;
    float2 p = verts[vid];
    out.position = float4(p, 0.0, 1.0);
    out.uv = p * 0.5 + 0.5;
    return out;
}

// MARK: - Helpers

static inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

static inline float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static inline float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * valueNoise(p);
        p = p * 2.02 + float2(11.3, 7.1);
        amplitude *= 0.5;
    }
    return value;
}

static inline float3 cosPalette(float t) {
    return 0.5 + 0.5 * cos(6.2831853 * (t + float3(0.00, 0.33, 0.67)));
}

static inline float2 rot2(float2 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Hexagonal / diamond metric. Gives polygonal stained-glass cells instead of
// soft circular blobs — the silhouette of cut gem shards.
static inline float polyMetric(float2 d, float seed) {
    float2 a = abs(d);
    float hex = max(a.x * 0.8660254 + a.y * 0.5, a.y);
    float dia = (a.x + a.y) * 0.70710678;
    float tri = max(a.x * 0.8660254 + d.y * 0.5, -d.y);
    float k = fract(seed * 7.13);
    if (k < 0.38) { return hex; }
    if (k < 0.72) { return dia; }
    return tri;
}

static inline float2 foldToWedge(float2 p, float segments) {
    float r = length(p);
    float a = atan2(p.y, p.x);
    float seg = (2.0 * M_PI_F) / max(segments, 1.0);
    a = a - seg * floor(a / seg);
    a = fabs(a - seg * 0.5);
    return float2(cos(a), sin(a)) * r;
}

static inline float mirrorRange(float x, float c) {
    float p = fmod(x, 2.0 * c);
    if (p < 0.0) { p += 2.0 * c; }
    return c - fabs(p - c);
}

// Compact ACES filmic curve — preserves jewel saturation better than Reinhard.
static inline float3 acesTonemap(float3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// MARK: - Pattern evaluation

static inline float3 evalPattern(float2 sp,
                                 float chromaScale,
                                 constant Uniforms &U,
                                 device const GPUParticle *particles) {
    float angle = atan2(sp.y, sp.x);
    float radius = length(sp) * chromaScale;
    float cellR = 1.05;
    radius = mirrorRange(radius, cellR);
    float2 q = float2(cos(angle), sin(angle)) * radius;

    float t = U.time * 0.04 * (1.0 - U.reduceMotion * 0.85);
    float n = fbm(q * 3.4 + float2(t, -t));

    int count = max(min(U.particleCount, KS_MAX_PARTICLES), 1);
    float bestD = 1e9;
    float secondD = 1e9;
    int best = 0;
    for (int i = 0; i < count; i++) {
        GPUParticle pt = particles[i];
        float2 delta = rot2(q - pt.position, -pt.rotation);
        float d = polyMetric(delta, pt.seed) - pt.radius * 1.05;
        if (d < bestD) {
            secondD = bestD;
            bestD = d;
            best = i;
        } else if (d < secondD) {
            secondD = d;
        }
    }

    GPUParticle bp = particles[best];
    float3 cellColor = bp.color.rgb;

    // Cut-glass interior: discrete facet planes from the shard orientation.
    float2 local = rot2(q - bp.position, -bp.rotation);
    float ang = atan2(local.y, local.x);
    float sides = 3.0 + floor(fract(bp.seed * 5.91) * 4.0);   // 3–6 cuts
    float ridges = abs(sin(ang * sides * 0.5));
    float plane = pow(ridges, 0.45);
    cellColor *= 0.72 + 0.42 * plane;

    // Harder core-to-edge falloff so each shard reads as a faceted gem, not a blob.
    float facet = clamp(1.0 - bestD * 1.15, 0.22, 1.35);
    float shimmer = 0.5 + 0.5 * sin(U.time * 1.6 + bp.seed * 30.0 + bestD * 14.0);
    cellColor *= facet;
    cellColor *= 1.0 + bp.refraction * U.refraction * shimmer * 0.18;

    float mo = 1.0 - U.reduceMotion;
    float energyBoost = 0.55 + U.motionEnergy * 0.85;

    float2 lightPos = float2(cos(U.time * 0.48), sin(U.time * 0.35)) * 0.52 * mo
                      + U.tilt * 0.85;
    float dL = length(q - lightPos);
    float illum = exp(-dL * dL * 1.8);

    float2 lightPos2 = float2(cos(U.time * -0.29 + 2.1), sin(U.time * 0.41 + 1.0)) * 0.48 * mo
                       - U.tilt * 0.55;
    float dL2 = length(q - lightPos2);
    float illum2 = exp(-dL2 * dL2 * 2.2);

    float3 irid = cosPalette(facet * 0.35 + bp.seed + dL * 0.2 + U.time * 0.03 * mo);
    cellColor = mix(cellColor, cellColor * 1.12 + irid * 0.32, illum * 0.32);

    float luma = dot(cellColor, float3(0.2126, 0.7152, 0.0722));
    cellColor = mix(float3(luma), cellColor, 1.22);          // punch saturation
    cellColor *= 1.0 + (illum * 0.85 + illum2 * 0.35) * energyBoost * (0.55 + U.glow);

    float2 sweepDir = float2(0.62, 0.78);
    float sweepPhase = sin(U.time * 0.55 * mo) * 1.2;
    float sweep = exp(-pow((dot(q, sweepDir) - sweepPhase) * 2.8, 2.0));
    cellColor *= 1.0 + sweep * 0.22;

    // Hairline metallic cames (solder between stained-glass pieces).
    float diff = secondD - bestD;
    float w = max(fwidth(diff) * 0.65, 0.0012);
    float border = smoothstep(0.0, w, diff);
    float3 cameDark = float3(0.07, 0.06, 0.05);
    float3 cameHi   = float3(0.78, 0.74, 0.66);
    float3 came = mix(cameDark, cameHi, 0.22 + illum * 0.55);
    float3 col = mix(came, cellColor, border);

    // Bright glass rim (Fresnel) just inside the came — sells thickness.
    float rim = (1.0 - smoothstep(0.0, w * 5.5, diff)) * border;
    col += cellColor * rim * 0.45;
    col += float3(1.0, 0.97, 0.92) * rim * 0.22;

    // Internal cut lines — thin bright scratches on the facet planes.
    float cut = smoothstep(0.08, 0.015, ridges) * border;
    col += float3(1.0, 0.98, 0.94) * cut * (0.18 + illum * 0.25);

    // Tight anisotropic glints along facet edges.
    float spec = exp(-dL * dL * 14.0) * smoothstep(0.75, 1.25, facet);
    spec += exp(-dL2 * dL2 * 18.0) * smoothstep(0.8, 1.3, facet) * 0.55;
    col += mix(float3(1.0), irid, 0.22) * spec * energyBoost * 0.7;

    col += cellColor * smoothstep(1.05, 1.32, facet) * U.bloom * 0.10;
    col *= 0.94 + 0.10 * n;
    return col;
}

// MARK: - Fragment stage

fragment float4 fragment_main(VSOut in [[stage_in]],
                              constant Uniforms &U [[buffer(KSBufferIndexUniforms)]],
                              device const GPUParticle *particles [[buffer(KSBufferIndexParticles)]]) {
    float2 res = U.resolution;
    float2 frag = in.position.xy;
    float2 uv = frag / res;
    float2 p = (frag - 0.5 * res) / min(res.x, res.y) * 2.0;

    float r2 = dot(p, p);
    p *= 1.0 + U.lensDistortion * 0.10 * r2;

    float ang = U.patternRotation + U.rotationZ;
    float ca = cos(ang);
    float sa = sin(ang);
    p = float2(ca * p.x - sa * p.y, sa * p.x + ca * p.y);
    p += U.tilt * 0.22 * (1.0 - U.reduceMotion);
    p /= max(U.zoom, 0.05);

    float2 sp = foldToWedge(p, U.segments);

    // Chromatic aberration only toward the screen edge so shard interiors stay crisp.
    float edgeAmt = smoothstep(0.45, 1.35, length(p));
    float camt = U.chromaticAberration * 0.006 * edgeAmt;
    float3 col;
    if (camt > 0.00015) {
        float rC = evalPattern(sp, 1.0 - camt, U, particles).r;
        float gC = evalPattern(sp, 1.0,         U, particles).g;
        float bC = evalPattern(sp, 1.0 + camt, U, particles).b;
        col = float3(rC, gC, bC);
    } else {
        col = evalPattern(sp, 1.0, U, particles);
    }

    col += pow(max(col - 0.82, float3(0.0)), float3(2.2)) * U.glow * 0.45;

    // Optical-tube vignette: darker corners, bright chamber — still full-screen.
    float vig = smoothstep(1.85, 0.18, length(uv * 2.0 - 1.0));
    col *= mix(1.0, vig, U.vignette * 0.85);
    col *= 0.90 + 0.14 * exp(-r2 * 0.35);

    col = acesTonemap(col * 1.18);
    col = pow(max(col, float3(0.0)), float3(0.96));

    float luma = dot(col, float3(0.2126, 0.7152, 0.0722));
    col = mix(float3(luma), col, 1.12);

    col = mix(col, saturate(col), U.reduceTransparency);
    return float4(col, 1.0);
}
