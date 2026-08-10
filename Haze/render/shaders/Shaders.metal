//
//  Shaders.metal
//  Haze — render/shaders
//

#include <metal_stdlib>
using namespace metal;

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

struct CompositeVSUniform {
    float4 dstRect;
    float4 srcUV;
};

vertex VSOut composite_vertex(uint vid [[vertex_id]],
                              constant CompositeVSUniform& u [[buffer(0)]]) {
    float2 pos[4] = { float2(u.dstRect.x, u.dstRect.y), float2(u.dstRect.z, u.dstRect.y),
                      float2(u.dstRect.x, u.dstRect.w), float2(u.dstRect.z, u.dstRect.w) };
    float2 uv[4]  = { float2(u.srcUV.x, u.srcUV.w), float2(u.srcUV.z, u.srcUV.w),
                      float2(u.srcUV.x, u.srcUV.y), float2(u.srcUV.z, u.srcUV.y) };
    VSOut o;
    o.position = float4(pos[vid], 0, 1);
    o.uv = uv[vid];
    return o;
}

struct QuadVSUniform {
    float2 p0;
    float2 p1;
    float2 p2;
    float2 p3;
};

vertex VSOut composite_quad_vertex(uint vid [[vertex_id]],
                                   constant QuadVSUniform& u [[buffer(0)]]) {
    float2 pos[4] = { u.p0, u.p1, u.p2, u.p3 };
    float2 uv[4]  = { float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0) };
    VSOut o;
    o.position = float4(pos[vid], 0, 1);
    o.uv = uv[vid];
    return o;
}

fragment float4 composite_frag(VSOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               sampler samp [[sampler(0)]],
                               constant float& opacity [[buffer(0)]]) {
    return tex.sample(samp, in.uv) * opacity;
}

fragment float4 composite_masked_frag(VSOut in [[stage_in]],
                                      texture2d<float> tex [[texture(0)]],
                                      texture2d<float> mask [[texture(1)]],
                                      sampler samp [[sampler(0)]],
                                      constant float& opacity [[buffer(0)]]) {
    float m = mask.sample(samp, in.uv).r;
    return tex.sample(samp, in.uv) * (opacity * m);
}

fragment float4 composite_blend_frag(VSOut in [[stage_in]],
                                     texture2d<float> tex [[texture(0)]],
                                     sampler samp [[sampler(0)]],
                                     constant float& opacity [[buffer(0)]],
                                     constant uint& mode [[buffer(1)]],
                                     float4 dst [[color(0)]]) {
    float4 s = tex.sample(samp, in.uv) * opacity;
    float as = s.a, ab = dst.a;
    float3 Cs = as > 0.0 ? s.rgb / as : float3(0.0);
    float3 Cb = ab > 0.0 ? dst.rgb / ab : float3(0.0);
    float3 B;
    switch (mode) {
        case 1u: B = Cb * Cs;               break;
        case 2u: B = Cb + Cs - Cb * Cs;     break;
        default: B = Cs;                    break;
    }
    float3 co = (1.0 - ab) * (as * Cs) + ab * (as * B) + (1.0 - as) * (ab * Cb);
    float  ao = as + ab * (1.0 - as);
    return float4(co, ao);
}

fragment float4 composite_blend_masked_frag(VSOut in [[stage_in]],
                                     texture2d<float> tex [[texture(0)]],
                                     texture2d<float> mask [[texture(1)]],
                                     sampler samp [[sampler(0)]],
                                     constant float& opacity [[buffer(0)]],
                                     constant uint& mode [[buffer(1)]],
                                     float4 dst [[color(0)]]) {
    float m = mask.sample(samp, in.uv).r;
    float4 s = tex.sample(samp, in.uv) * (opacity * m);
    float as = s.a, ab = dst.a;
    float3 Cs = as > 0.0 ? s.rgb / as : float3(0.0);
    float3 Cb = ab > 0.0 ? dst.rgb / ab : float3(0.0);
    float3 B;
    switch (mode) {
        case 1u: B = Cb * Cs;               break;
        case 2u: B = Cb + Cs - Cb * Cs;     break;
        default: B = Cs;                    break;
    }
    float3 co = (1.0 - ab) * (as * Cs) + ab * (as * B) + (1.0 - as) * (ab * Cb);
    float  ao = as + ab * (1.0 - as);
    return float4(co, ao);
}

vertex VSOut present_vertex(uint vid [[vertex_id]],
                            constant float4x4& mvp [[buffer(0)]]) {
    float2 pos[4] = { float2(-0.5, -0.5), float2(0.5, -0.5), float2(-0.5, 0.5), float2(0.5, 0.5) };
    float2 uv[4]  = { float2(0, 1),      float2(1, 1),      float2(0, 0),      float2(1, 0) };
    VSOut o;
    o.position = mvp * float4(pos[vid], 0, 1);
    o.uv = uv[vid];
    return o;
}

fragment float4 present_frag(VSOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             sampler samp [[sampler(0)]]) {
    return tex.sample(samp, in.uv);
}

struct BrushUniforms {
    float4x4 ortho;
    float4 color;
    float2 center;
    float radius;
    float hardness;
    float flow;
    float opacityCeil;
    float angle;
    float roundness;
    float footprint;
    float tipContent;
};

struct BrushOut {
    float4 position [[position]];
    float2 local;
};

vertex BrushOut brush_vertex(uint vid [[vertex_id]],
                             constant BrushUniforms& u [[buffer(0)]]) {
    float2 off[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    float2 corner = u.center + off[vid] * u.radius * u.footprint;
    BrushOut o;
    o.position = u.ortho * float4(corner, 0, 1);
    o.local = off[vid];
    return o;
}

fragment float4 brush_frag(BrushOut in [[stage_in]],
                           constant BrushUniforms& u [[buffer(0)]]) {
    float d = length(in.local);
    float a = 1.0 - smoothstep(u.hardness, 1.0, d);
    float alpha = u.color.a * a * u.flow;
    return float4(u.color.rgb * alpha, alpha);
}

static inline float2 tip_uv(float2 local, float angle, float roundness) {
    float c = cos(angle), s = sin(angle);
    float2 r = float2(local.x * c + local.y * s, -local.x * s + local.y * c);
    r.y /= max(roundness, 0.05);
    return r;
}

fragment float4 brush_textured_frag(BrushOut in [[stage_in]],
                                    constant BrushUniforms& u [[buffer(0)]],
                                    texture2d<float> tip [[texture(0)]],
                                    sampler samp [[sampler(0)]]) {
    float2 r = tip_uv(in.local * u.footprint, u.angle, u.roundness);
    if (any(abs(r) > 1.0)) return float4(0.0);
    float coverage = tip.sample(samp, r * (u.tipContent * 0.5) + 0.5).r;
    float alpha = u.color.a * coverage * u.flow;
    return float4(u.color.rgb * alpha, alpha);
}

fragment float4 brush_textured_ceiling_frag(BrushOut in [[stage_in]],
                                    constant BrushUniforms& u [[buffer(0)]],
                                    texture2d<float> tip [[texture(0)]],
                                    sampler samp [[sampler(0)]]) {
    float2 r = tip_uv(in.local * u.footprint, u.angle, u.roundness);
    if (any(abs(r) > 1.0)) discard_fragment();
    float coverage = tip.sample(samp, r * (u.tipContent * 0.5) + 0.5).r;
    if (coverage <= 0.0) discard_fragment();
    return float4(u.opacityCeil, 0.0, 0.0, u.opacityCeil);
}

fragment float4 brush_ceiling_frag(BrushOut in [[stage_in]],
                                   constant BrushUniforms& u [[buffer(0)]]) {
    float d = length(in.local);
    float a = 1.0 - smoothstep(u.hardness, 1.0, d);
    if (a <= 0.0) discard_fragment();
    return float4(u.opacityCeil, 0.0, 0.0, u.opacityCeil);
}

fragment float4 scratch_resolve_frag(VSOut in [[stage_in]],
                                     texture2d<float> scratch [[texture(0)]],
                                     texture2d<float> ceiling [[texture(1)]],
                                     sampler samp [[sampler(0)]]) {
    float4 s = scratch.sample(samp, in.uv);
    float cap = ceiling.sample(samp, in.uv).r;
    float a = s.a;
    float scale = a > 0.0 ? min(a, cap) / a : 0.0;
    return s * scale;
}
