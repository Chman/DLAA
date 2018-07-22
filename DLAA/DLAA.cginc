//
// Directionally Localized Anti-Aliasing (DLAA)
// Original method by Dmitry Andreev - Copyright (C) LucasArts 2010-2011
// http://and.intercon.ru/releases/talks/dlaagdc2011/
//
// Modified & adapted to run in Unity
//

#include "UnityCG.cginc"

struct Attributes
{
    float4 vertex : POSITION;
    float2 uv : TEXCOORD0;
};

struct Varyings
{
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD0;
};

Varyings Vert(Attributes v)
{
    Varyings o;
    o.pos = UnityObjectToClipPos(v.vertex);
    o.uv = v.uv;
    return o;
}

Texture2D _MainTex;
SamplerState sampler_MainTex;

float4 _MainTex_TexelSize;

// As counter-intuitive as it sounds, and like FXAA, DLAA works best when fed sRGB encoded colors.
// We don't need an exact conversion so we'll just use a very basic approximation.
// Note: this effect should be applied after tonemapping.
float3 ToLinear(float3 x)
{
    #if !UNITY_COLORSPACE_GAMMA
    x = x * x;
    #endif

    return x;
}

float3 ToGamma(float3 x)
{
    #if !UNITY_COLORSPACE_GAMMA
    x = sqrt(x);
    #endif

    return x;
}

float4 LoadPixel(int2 icoords, int idx, int idy)
{
    return _MainTex.Load(int3(icoords + int2(idx, idy), 0));
}

float4 SamplePixel(float2 coords, float dx, float dy)
{
    return _MainTex.SampleLevel(sampler_MainTex, coords + float2(dx, dy) * _MainTex_TexelSize.xy, 0);
}

float Luminance(float3 rgb)
{
    // sRGB primaries and D65 white point
    return dot(rgb, float3(0.2126729, 0.7151522, 0.0721750));
}

float4 FragPreFilter(Varyings i) : SV_Target
{
    int2 icoords = _MainTex_TexelSize.zw * i.uv;
    float3 center = LoadPixel(icoords,  0,  0).xyz;
    float3 left   = LoadPixel(icoords, -1,  0).xyz;
    float3 right  = LoadPixel(icoords,  1,  0).xyz;
    float3 top    = LoadPixel(icoords,  0, -1).xyz;
    float3 bottom = LoadPixel(icoords,  0,  1).xyz;

    float3 edges = 4.0 * abs((left + right + top + bottom) - 4.0 * center);
    float  edgesLum = Luminance(ToGamma(edges));

    return float4(ToGamma(center), edgesLum);
}

float4 FragDLAA(Varyings i) : SV_Target
{
    int2 icoords = _MainTex_TexelSize.zw * i.uv;

    // ------------------------------------------------------------
    // Short Edges
    //

    // 5x5 cross
    float4 center    = LoadPixel(icoords, 0, 0);
    float4 left_01   = SamplePixel(i.uv, -1.5,  0.0);
    float4 right_01  = SamplePixel(i.uv,  1.5,  0.0);
    float4 top_01    = SamplePixel(i.uv,  0.0, -1.5);
    float4 bottom_01 = SamplePixel(i.uv,  0.0,  1.5);

    float4 w_h = 2.0 * (left_01 + right_01);
    float4 w_v = 2.0 * (top_01 + bottom_01);

    // 5-pixel wide high-pass
    float4 edge_h = abs(w_h - 4.0 * center) / 4.0;
    float4 edge_v = abs(w_v - 4.0 * center) / 4.0;

    float4 blurred_h = (w_h + 2.0 * center) / 6.0;
    float4 blurred_v = (w_v + 2.0 * center) / 6.0;

    float edge_h_lum    = Luminance(edge_h.xyz);
    float edge_v_lum    = Luminance(edge_v.xyz);
    float blurred_h_lum = Luminance(blurred_h.xyz);
    float blurred_v_lum = Luminance(blurred_v.xyz);

    const float kLambda = 3.0;
    const float kEpsilon = 0.1;
    float edge_mask_h = saturate((kLambda * edge_h_lum - kEpsilon) / blurred_v_lum);
    float edge_mask_v = saturate((kLambda * edge_v_lum - kEpsilon) / blurred_h_lum);

    float4 clr = center;
    clr = lerp(clr, blurred_h, edge_mask_v);
    clr = lerp(clr, blurred_v, edge_mask_h * 0.5);

    // ------------------------------------------------------------
    // Long Edges
    //

    // 16x16 cross
    float4 h0 = right_01;
    float4 h1 = SamplePixel(i.uv,  3.5,  0.0);
    float4 h2 = SamplePixel(i.uv,  5.5,  0.0);
    float4 h3 = SamplePixel(i.uv,  7.5,  0.0);
    float4 h4 = left_01;
    float4 h5 = SamplePixel(i.uv, -3.5,  0.0);
    float4 h6 = SamplePixel(i.uv, -5.5,  0.0);
    float4 h7 = SamplePixel(i.uv, -7.5,  0.0);
    float4 v0 = bottom_01;
    float4 v1 = SamplePixel(i.uv,  0.0,  3.5);
    float4 v2 = SamplePixel(i.uv,  0.0,  5.5);
    float4 v3 = SamplePixel(i.uv,  0.0,  7.5);
    float4 v4 = top_01;
    float4 v5 = SamplePixel(i.uv,  0.0, -3.5);
    float4 v6 = SamplePixel(i.uv,  0.0, -5.5);
    float4 v7 = SamplePixel(i.uv,  0.0, -7.5);

    float long_edge_mask_h = (h0.a + h1.a + h2.a + h3.a + h4.a + h5.a + h6.a + h7.a) / 8.0;
    float long_edge_mask_v = (v0.a + v1.a + v2.a + v3.a + v4.a + v5.a + v6.a + v7.a) / 8.0;

    long_edge_mask_h = saturate(long_edge_mask_h * 2.0 - 1.0);
    long_edge_mask_v = saturate(long_edge_mask_v * 2.0 - 1.0);

    if (abs(long_edge_mask_h - long_edge_mask_v) > 0.2)
    {
        float4 left   = LoadPixel(icoords, -1,  0);
        float4 right  = LoadPixel(icoords,  1,  0);
        float4 top    = LoadPixel(icoords,  0, -1);
        float4 bottom = LoadPixel(icoords,  0,  1);

        float4 long_blurred_h = (h0 + h1 + h2 + h3 + h4 + h5 + h6 + h7) / 8.0;
        float4 long_blurred_v = (v0 + v1 + v2 + v3 + v4 + v5 + v6 + v7) / 8.0;

        float lb_h_lum = Luminance(long_blurred_h.xyz);
        float lb_v_lum = Luminance(long_blurred_v.xyz);

        float center_lum = Luminance(center.xyz);
        float left_lum   = Luminance(left.xyz);
        float right_lum  = Luminance(right.xyz);
        float top_lum    = Luminance(top.xyz);
        float bottom_lum = Luminance(bottom.xyz);

        float4 clr_v = center;
        float4 clr_h = center;

        float hx = saturate(0.0 + (lb_h_lum - top_lum)    / (center_lum - top_lum));
        float hy = saturate(1.0 + (lb_h_lum - center_lum) / (center_lum - bottom_lum));
        float vx = saturate(0.0 + (lb_v_lum - left_lum)   / (center_lum - left_lum));
        float vy = saturate(1.0 + (lb_v_lum - center_lum) / (center_lum - right_lum));

        float4 vhxy = float4(vx, vy, hx, hy);
        vhxy = vhxy == float4(0, 0, 0, 0) ? float4(1, 1, 1, 1) : vhxy;

        clr_v = lerp(left, clr_v, vhxy.x);
        clr_v = lerp(right, clr_v, vhxy.y);
        clr_h = lerp(top, clr_h, vhxy.z);
        clr_h = lerp(bottom, clr_h, vhxy.w);

        clr = lerp(clr, clr_v, long_edge_mask_v);
        clr = lerp(clr, clr_h, long_edge_mask_h);
    }

    #if defined(PRESERVE_HIGHLIGHTS)
    {
        float4 r0 = SamplePixel(i.uv, -1.5, -1.5);
        float4 r1 = SamplePixel(i.uv,  1.5, -1.5);
        float4 r2 = SamplePixel(i.uv, -1.5,  1.5);
        float4 r3 = SamplePixel(i.uv,  1.5,  1.5);

        float4 r = (4.0 * (r0 + r1 + r2 + r3) + center + top_01 + bottom_01 + left_01 + right_01) / 25.0;
        clr = lerp(clr, center, saturate(r.a * 3.0 - 1.5));
    }
    #endif

    return float4(ToLinear(clr.xyz), 1.0);
}
