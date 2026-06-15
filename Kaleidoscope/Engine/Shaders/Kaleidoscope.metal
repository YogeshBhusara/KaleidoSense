//
//  Kaleidoscope.metal
//  KaleidoSense
//
//  GPU kaleidoscope renderer. A single full-screen fragment pass performs:
//    1. Lens / barrel distortion of the screen coordinate.
//    2. Motion-driven rotation and translation of the sampling point.
//    3. Dihedral (mirror + radial) symmetry folding into a base wedge.
//    4. Procedural "stained glass" background + soft glass-fragment blobs.
//    5. Chromatic aberration, bloom, glow, vignette and tone mapping.
//
//  Everything is evaluated analytically per pixel, so there is no texture
//  upload cost and the renderer scales cleanly from 60 to 120 FPS.
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
    // Oversized triangle that covers the whole clip space in a single primitive.
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

// MARK: - Hash / value noise / fBm helpers

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
    for (int i = 0; i < 5; i++) {
        value += amplitude * valueNoise(p);
        p = p * 2.02 + float2(11.3, 7.1);
        amplitude *= 0.5;
    }
    return value;
}

// Iridescent / thin-film cosine palette (Inigo Quilez style). Produces smooth
// rainbow shifts used to tint the glass under the moving light.
static inline float3 cosPalette(float t) {
    return 0.5 + 0.5 * cos(6.2831853 * (t + float3(0.0, 0.33, 0.67)));
}

// MARK: - Symmetry fold

// Folds a point into the base dihedral wedge so symmetric output pixels map to
// the same sample location, producing true mirror + rotational symmetry.
static inline float2 foldToWedge(float2 p, float segments) {
    float r = length(p);
    float a = atan2(p.y, p.x);
    float seg = (2.0 * M_PI_F) / max(segments, 1.0);
    a = a - seg * floor(a / seg);   // wrap into [0, seg)
    a = fabs(a - seg * 0.5);        // mirror within the wedge
    return float2(cos(a), sin(a)) * r;
}

// MARK: - Pattern evaluation (the "object chamber")

// Mirror-tiles a scalar into [0, c] (triangle wave) so the pattern repeats and
// fills the whole screen instead of fading out to background past the chamber.
static inline float mirrorRange(float x, float c) {
    float p = fmod(x, 2.0 * c);
    if (p < 0.0) { p += 2.0 * c; }
    return c - fabs(p - c);
}

// Renders crisp "glass shard" cells using an additively-weighted Voronoi over
// the fragment positions. Every pixel belongs to the nearest shard, so the
// pattern covers the whole field (no ring / no dark centre). Thin dark lines at
// cell boundaries read as the leading/cames between pieces of stained glass.
//
// `chromaScale` evaluates the field at a slightly different radius per color
// channel for subtle chromatic aberration.
static inline float3 evalPattern(float2 sp,
                                 float chromaScale,
                                 constant Uniforms &U,
                                 device const GPUParticle *particles) {
    // Radial mirror-tiling: keep the folded angle, repeat the radius outward so
    // the rosette tessellates across the entire screen.
    float angle = atan2(sp.y, sp.x);
    float radius = length(sp) * chromaScale;
    float cellR = 1.05;                                   // matches chamber radius
    radius = mirrorRange(radius, cellR);
    float2 q = float2(cos(angle), sin(angle)) * radius;

    // Faint procedural depth that only shows through the leading lines.
    float t = U.time * 0.05 * (1.0 - U.reduceMotion * 0.85);
    float n = fbm(q * 2.2 + float2(t, -t));

    // Additively-weighted Voronoi: larger shards (radius) claim larger cells.
    int count = max(min(U.particleCount, KS_MAX_PARTICLES), 1);
    float bestD = 1e9;
    float secondD = 1e9;
    int best = 0;
    for (int i = 0; i < count; i++) {
        GPUParticle pt = particles[i];
        float d = length(q - pt.position) - pt.radius * 1.7;
        if (d < bestD) {
            secondD = bestD; bestD = d; best = i;
        } else if (d < secondD) {
            secondD = d;
        }
    }

    GPUParticle bp = particles[best];
    float3 cellColor = bp.color.rgb;

    // Faceted gem shading: brighter toward the seed, darker toward the edges,
    // with an animated refraction shimmer per shard.
    float facet = clamp(1.0 - bestD * 0.7, 0.28, 1.25);
    float shimmer = 0.5 + 0.5 * sin(U.time * 2.0 + bp.seed * 30.0 + bestD * 12.0);
    cellColor *= facet;
    cellColor *= 1.0 + bp.refraction * U.refraction * shimmer * 0.22;

    // --- Dynamic lighting -------------------------------------------------
    // A primary light orbits slowly and is pushed around by device tilt, so on
    // a real iPhone the highlights and color shifts track how you hold it. A
    // second, counter-orbiting light and a moving light sweep add liveliness.
    float mo = 1.0 - U.reduceMotion;                 // freeze when Reduce Motion
    float energyBoost = 0.6 + U.motionEnergy * 0.9;  // brighter when moving

    float2 lightPos = float2(cos(U.time * 0.5), sin(U.time * 0.37)) * 0.55 * mo
                      + U.tilt * 0.9;
    float dL = length(q - lightPos);
    float illum = exp(-dL * dL * 1.4);

    float2 lightPos2 = float2(cos(U.time * -0.31 + 2.0), sin(U.time * 0.43 + 1.0)) * 0.5 * mo
                       - U.tilt * 0.6;
    float dL2 = length(q - lightPos2);
    float illum2 = exp(-dL2 * dL2 * 1.8);

    // Iridescent thin-film tint that shifts with the light and per shard.
    float3 irid = cosPalette(facet * 0.5 + bp.seed + dL * 0.25 + U.time * 0.04 * mo);
    cellColor = mix(cellColor, cellColor * 1.15 + irid * 0.55, illum * 0.4);

    // Light enhances brightness and saturation where it falls.
    float3 lum = float3(dot(cellColor, float3(0.299, 0.587, 0.114)));
    cellColor = mix(cellColor, mix(lum, cellColor, 1.6), illum * 0.5);   // saturate
    cellColor *= 1.0 + (illum * 1.1 + illum2 * 0.45) * energyBoost * (0.6 + U.glow);

    // Travelling light sweep (a soft bright band gliding across the field).
    float2 sweepDir = float2(0.6, 0.8);
    float sweepPhase = sin(U.time * 0.6 * mo) * 1.3;
    float sweep = exp(-pow((dot(q, sweepDir) - sweepPhase) * 2.4, 2.0));
    cellColor *= 1.0 + sweep * 0.35;

    // Crisp leading line: where the two nearest shards are nearly equidistant.
    // `fwidth` keeps the edge exactly one pixel wide (anti-aliased but sharp).
    float diff = secondD - bestD;
    float w = fwidth(diff) * 1.5 + 0.005;
    float border = smoothstep(0.0, w, diff);
    float3 lead = U.background.rgb * 0.18;
    float3 col = mix(lead, cellColor, border);

    // Crisp specular glints: tight highlight on facets nearest the light.
    float spec = exp(-dL * dL * 9.0) * smoothstep(0.6, 1.2, facet);
    spec += exp(-dL2 * dL2 * 12.0) * smoothstep(0.7, 1.2, facet) * 0.6;
    float3 specCol = mix(float3(1.0), irid, 0.35);
    col += specCol * spec * energyBoost * 0.9;

    // Tight bloom on only the brightest shards (kept crisp, not a blur).
    col += cellColor * smoothstep(1.0, 1.25, facet) * U.bloom * 0.15;

    // Subtle depth modulation from the procedural field.
    col *= 0.9 + 0.2 * n;
    return col;
}

// MARK: - Fragment stage

fragment float4 fragment_main(VSOut in [[stage_in]],
                              constant Uniforms &U [[buffer(KSBufferIndexUniforms)]],
                              device const GPUParticle *particles [[buffer(KSBufferIndexParticles)]]) {
    float2 res = U.resolution;
    float2 frag = in.position.xy;
    float2 uv = frag / res;                      // 0...1 across the drawable
    // Isotropic centered coordinates: a circle stays a circle in portrait.
    float2 p = (frag - 0.5 * res) / min(res.x, res.y) * 2.0;

    // Barrel / lens distortion.
    float r2 = dot(p, p);
    p *= 1.0 + U.lensDistortion * 0.18 * r2;

    // Rotate by idle drift + device yaw, then translate by tilt for parallax.
    float ang = U.patternRotation + U.rotationZ;
    float ca = cos(ang);
    float sa = sin(ang);
    p = float2(ca * p.x - sa * p.y, sa * p.x + ca * p.y);
    p += U.tilt * 0.25 * (1.0 - U.reduceMotion);

    // Zoom (smaller value -> more magnified).
    p /= max(U.zoom, 0.05);

    // Symmetry fold.
    float2 sp = foldToWedge(p, U.segments);

    // Chromatic aberration: evaluate the pattern at slightly different scales
    // per channel. Kept subtle so the crisp shard edges stay clean.
    float camt = U.chromaticAberration * 0.010;
    float3 col;
    if (camt > 0.0001) {
        float rC = evalPattern(sp, 1.0 - camt, U, particles).r;
        float gC = evalPattern(sp, 1.0,         U, particles).g;
        float bC = evalPattern(sp, 1.0 + camt, U, particles).b;
        col = float3(rC, gC, bC);
    } else {
        col = evalPattern(sp, 1.0, U, particles);
    }

    // Gentle additive glow on the brightest regions only.
    col += pow(max(col - 0.75, float3(0.0)), float3(2.0)) * U.glow * 0.6;

    // Vignette.
    float vig = smoothstep(1.7, 0.2, length(uv * 2.0 - 1.0));
    col *= mix(1.0, vig, U.vignette);

    // Filmic exposure tone map: naturally rolls off highlights so dense
    // particle/halo regions stay rich and saturated instead of clipping white.
    col = 1.0 - exp(-col * 1.25);
    col = pow(max(col, float3(0.0)), float3(0.92));

    // Respect Reduce Transparency by flattening toward a solid look.
    col = mix(col, clamp(col, 0.0, 1.0), U.reduceTransparency);

    return float4(col, 1.0);
}
