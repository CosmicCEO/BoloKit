//
//  MetalTileRenderer.metal
//  Bolo 2026
//
//  v1.6.0 (#25) increment 4: instanced textured-quad shader for terrain tiles. One instance
//  per visible tile; the vertex shader places a unit quad at the instance's pixel-space origin
//  and samples the shared tile sheet texture at the instance's own UV cell -- the GPU
//  equivalent of `GameRenderView.drawTerrain`'s per-tile `tilesImage.cropping(to:)` + `blit()`.
//
//  Coordinate convention: `targetSize` is the offscreen render target's pixel size, with
//  (0, 0) at its top-left corner and Y increasing downward -- matching this app's own
//  top-left-origin, +y-down convention (`GameRenderView.swift`'s own header, D66) rather than
//  Metal's default bottom-left NDC. `MetalTileRenderer.swift` composites the resulting CGImage
//  back into the CPU `CGContext` via `GameRenderView.blit(_:in:_:)`, which already handles
//  Core Graphics' own separate row-0-at-high-Y quirk for `CGImage` drawing -- so this shader
//  only has to be internally consistent with its own texture atlas' cell layout (also
//  top-left-origin, D66), not pre-compensate for CG's blit quirk itself.

#include <metal_stdlib>
using namespace metal;

struct TileInstance {
    float2 origin;   // top-left pixel position of this tile's quad, in render-target space
    float2 uvOrigin; // top-left UV coordinate (0...1) of this tile's cell in the sheet texture
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

constant float2 kUnitQuad[4] = {
    float2(0.0, 0.0),
    float2(1.0, 0.0),
    float2(0.0, 1.0),
    float2(1.0, 1.0)
};

vertex VertexOut tileVertexMain(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant TileInstance *instances [[buffer(0)]],
    constant float2 &targetSize [[buffer(1)]],
    constant float &tileSizePixels [[buffer(2)]],
    constant float &uvCellSize [[buffer(3)]]
) {
    TileInstance inst = instances[instanceID];
    float2 corner = kUnitQuad[vertexID];
    float2 pixelPos = inst.origin + corner * tileSizePixels;

    float2 ndc;
    ndc.x = (pixelPos.x / targetSize.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (pixelPos.y / targetSize.y) * 2.0;

    VertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.uv = inst.uvOrigin + corner * uvCellSize;
    return out;
}

fragment float4 tileFragmentMain(
    VertexOut in [[stage_in]],
    texture2d<float> sheet [[texture(0)]],
    sampler sheetSampler [[sampler(0)]]
) {
    return sheet.sample(sheetSampler, in.uv);
}
