//
//  MetalTileRenderer.swift
//  Bolo 2026
//
//  v1.6.0 (#25) increment 4: a `TileRenderer` that draws terrain via a real Metal render
//  pipeline (`MetalTileRenderer.metal`) instead of `CGContextTileRenderer`'s per-tile
//  `CGContext` blits. Deliberately conforms to the same `TileRenderer` seam
//  (`draw(_:ctx:dirtyRect:)`) `CGContextTileRenderer` does, so it's a drop-in swap and directly
//  comparable through `Tests/.../RenderParityHarness.swift` -- this increment is about
//  correctness parity, not yet the live on-screen performance win (that's the floating
//  `CAMetalLayer` subview wired up in a later increment). It renders into an offscreen
//  `MTLTexture` sized to `dirtyRect`, converts that to a `CGImage`, and composites it into the
//  passed-in `ctx` via `GameRenderView.blit(_:in:_:)` -- reusing the same flip-compensated
//  compositing path every other draw call already goes through, rather than re-deriving
//  Core Graphics' own row-0-at-high-Y quirk a second time.
//
//  Sprites/shells/explosions and the mine overlay are still drawn by `view.drawSprites(ctx)`
//  in this increment -- only terrain moves to Metal here. `draw(_:ctx:dirtyRect:)` still calls
//  `view.drawSprites(ctx)` directly after the Metal terrain pass, matching
//  `CGContextTileRenderer`'s own draw order.

import AppKit
import CoreImage
import Metal
import MetalKit
import BoloKit

/// `nil` on any Metal setup failure (no GPU, shader compile failure, etc.) -- callers should
/// fall back to `CGContextTileRenderer` rather than force-unwrap. Metal is expected to be
/// available on every supported macOS host for this app, so a `nil` here in production would
/// itself be a signal something is wrong, not a routine path.
public final class MetalTileRenderer: TileRenderer {
    private static let tileSizePixels: Float = 16
    private static let sheetPixelSize: Float = 256
    private static let sheetCellsPerAxis: Float = sheetPixelSize / tileSizePixels // 16

    private struct TileInstance {
        var origin: SIMD2<Float>
        var uvOrigin: SIMD2<Float>
    }

    /// v1.6.0 (#25) increment 6: `internal`, not `private` -- `LiveMetalTerrainOverlay` reuses
    /// this same device for its `MTKView` rather than creating a second one via a separate
    /// `MTLCreateSystemDefaultDevice()` call.
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let ciContext: CIContext
    private let textureLoader: MTKTextureLoader

    /// Cached uploads, keyed by source `CGImage` identity -- `tilesImage`/`spritesImage` are
    /// each generated once at app launch and never change, so each uploads at most once per
    /// `MetalTileRenderer` instance, not per frame. Two distinct sheets (tiles, sprites) are
    /// ever passed in, so a tiny linear cache is simpler than a hashable-CGImage dictionary.
    private var textureCache: [(image: CGImage, texture: MTLTexture)] = []

    /// v1.6.0 (#25) increment 5: a rendered-once-per-index cache of individual sprite cells
    /// (each exactly 16x16, isolated, matching `CGContextTileRenderer`'s own per-cell crop
    /// granularity from the start -- no cross-cell interpolation bleed to guard against here,
    /// unlike terrain's whole-dirty-region composite in `draw(_:ctx:dirtyRect:)`). A sprite
    /// sheet has on the order of 150 distinct indices total (`SELETRIMAGE` is the highest),
    /// reused across every tank/shell/explosion instance in every frame, so this cache is
    /// small and effectively fills once.
    private var spriteCellCache: [Int32: CGImage] = [:]

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
            let queue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let vertexFn = library.makeFunction(name: "tileVertexMain"),
            let fragmentFn = library.makeFunction(name: "tileFragmentMain")
        else { return nil }
        self.device = device
        self.commandQueue = queue
        self.textureLoader = MTKTextureLoader(device: device)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFn
        pipelineDescriptor.fragmentFunction = fragmentFn
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            return nil
        }
        self.pipelineState = pipelineState

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else { return nil }
        self.sampler = sampler

        self.ciContext = CIContext(mtlDevice: device, options: [.workingColorSpace: NSNull()])
    }

    private func texture(for cgImage: CGImage) -> MTLTexture? {
        if let cached = textureCache.first(where: { $0.image === cgImage }) {
            return cached.texture
        }
        // `.origin: .topLeft` keeps texture row 0 == the source `CGImage`'s row 0, matching
        // this codebase's own top-left-origin sheet convention (D66) -- MTKTextureLoader's
        // un-optioned default otherwise flips vertically for GL-heritage reasons that don't
        // apply here.
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .origin: MTKTextureLoader.Origin.topLeft,
            .generateMipmaps: false,
        ]
        guard let texture = try? textureLoader.newTexture(cgImage: cgImage, options: options) else { return nil }
        textureCache.append((cgImage, texture))
        return texture
    }

    /// Renders (or returns the cached render of) a single sprite sheet cell in isolation --
    /// the Metal-sourced counterpart to `spritesImage.cropping(to: sheetSrcRect(forIndex:))`.
    private func spriteCell(forIndex index: Int32, spritesTexture: MTLTexture) -> CGImage? {
        if let cached = spriteCellCache[index] { return cached }
        let instance = [TileInstance(origin: .zero, uvOrigin: Self.uvOrigin(forIndex: index))]
        guard let cell = renderInstances(
            instance, sheetTexture: spritesTexture, targetWidth: Self.tileSizePixels, targetHeight: Self.tileSizePixels
        ) else { return nil }
        spriteCellCache[index] = cell
        return cell
    }

    /// Same tile-range math as `GameRenderView.drawTerrain`, so both renderers draw exactly the
    /// same set of tiles for a given `dirtyRect`.
    private static func tileRange(for dirtyRect: NSRect) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
        let tile = Int(tileSizePixels)
        let minX = max(0, Int(dirtyRect.minX) / tile)
        let maxX = min(255, Int(dirtyRect.maxX.rounded(.up)) / tile)
        let minY = max(0, Int(dirtyRect.minY) / tile)
        let maxY = min(255, Int(dirtyRect.maxY.rounded(.up)) / tile)
        guard minX <= maxX, minY <= maxY else { return nil }
        return (minX, maxX, minY, maxY)
    }

    private static func uvOrigin(forIndex index: Int32) -> SIMD2<Float> {
        let row = Float(Int(index) >> 4)
        let col = Float(Int(index) & 0xF)
        return SIMD2<Float>(col, row) / sheetCellsPerAxis
    }

    public func draw(_ view: GameRenderView, ctx: CGContext, dirtyRect: NSRect) {
        guard let sheetTexture = texture(for: view.tilesImage),
            let range = Self.tileRange(for: dirtyRect)
        else {
            // Falls back to the CPU path for this frame rather than drawing nothing -- a
            // texture-upload or empty-range failure shouldn't blank the screen.
            view.drawTerrain(ctx, dirtyRect: dirtyRect)
            view.drawSprites(ctx)
            return
        }

        let originXPixels = Float(range.minX) * Self.tileSizePixels
        let originYPixels = Float(range.minY) * Self.tileSizePixels
        let widthPixels = Float(range.maxX - range.minX + 1) * Self.tileSizePixels
        let heightPixels = Float(range.maxY - range.minY + 1) * Self.tileSizePixels

        var instances: [TileInstance] = []
        instances.reserveCapacity((range.maxX - range.minX + 1) * (range.maxY - range.minY + 1) * 2)
        for y in range.minY...range.maxY {
            for x in range.minX...range.maxX {
                let localOrigin = SIMD2<Float>(
                    Float(x) * Self.tileSizePixels - originXPixels,
                    Float(y) * Self.tileSizePixels - originYPixels
                )
                let index = unseenTileAsSeaImage(mapimage(view.tileGrid, Int32(x), Int32(y)))
                instances.append(TileInstance(origin: localOrigin, uvOrigin: Self.uvOrigin(forIndex: index)))
                if isMinedTile(view.tileGrid, Int32(x), Int32(y)) != 0 {
                    instances.append(TileInstance(origin: localOrigin, uvOrigin: Self.uvOrigin(forIndex: MINE00IMAGE)))
                }
            }
        }
        guard !instances.isEmpty,
            let renderedImage = renderInstances(
                instances, sheetTexture: sheetTexture, targetWidth: widthPixels, targetHeight: heightPixels
            )
        else {
            view.drawTerrain(ctx, dirtyRect: dirtyRect)
            view.drawSprites(ctx)
            return
        }

        // CPU `drawTerrain` draws each 16x16 cell as its own separate `ctx.draw()` call, so
        // Core Graphics' default image interpolation (used unchanged everywhere else in this
        // app) only ever smooths within one tile's own anti-aliased edges, never bleeds across
        // a boundary into a neighboring, different tile -- each cell is drawn in isolation.
        // Blitting this renderer's whole composited region in one call broke that: CG smoothed
        // across internal tile boundaries within the single large image (found via the parity
        // harness, not a hypothetical -- forcing `.none` interpolation fixed the cross-tile
        // bleed but then mismatched CPU's own default-interpolation smoothing *within* each
        // tile's edges). Cropping back into per-tile sub-images before blitting reproduces
        // CPU's exact compositing granularity -- same call shape, same interpolation settings,
        // only the *source* of each cell's pixels differs (GPU sample vs. CGImage crop).
        for y in range.minY...range.maxY {
            for x in range.minX...range.maxX {
                let localX = CGFloat(x - range.minX) * CGFloat(Self.tileSizePixels)
                let localY = CGFloat(y - range.minY) * CGFloat(Self.tileSizePixels)
                let cellRect = CGRect(x: localX, y: localY, width: CGFloat(Self.tileSizePixels), height: CGFloat(Self.tileSizePixels))
                guard let cell = renderedImage.cropping(to: cellRect) else { continue }
                let dst = CGRect(x: CGFloat(x) * CGFloat(Self.tileSizePixels), y: CGFloat(y) * CGFloat(Self.tileSizePixels), width: CGFloat(Self.tileSizePixels), height: CGFloat(Self.tileSizePixels))
                view.blit(cell, in: dst, ctx)
            }
        }
        drawSpritesViaMetal(view, ctx: ctx)
    }

    /// v1.6.0 (#25) increment 5: sprites/shells/explosions/builders. Every positioning,
    /// alliance-coloring, fog-fade, heading, and animation-frame decision stays in
    /// `GameRenderView.drawSprites`/`drawBuilder`/`drawSprite` itself, unchanged -- this only
    /// swaps out where a sprite cell's pixels come from, via `spriteCellProvider`. Falls back
    /// to the plain CPU sprite draw if the sprites sheet fails to upload.
    private func drawSpritesViaMetal(_ view: GameRenderView, ctx: CGContext) {
        guard let spritesTexture = texture(for: view.spritesImage) else {
            view.drawSprites(ctx)
            return
        }
        view.spriteCellProvider = { [weak self] index in
            self?.spriteCell(forIndex: index, spritesTexture: spritesTexture)
        }
        view.drawSprites(ctx)
        view.spriteCellProvider = nil
    }

    /// v1.6.0 (#25) increment 6: makes a command buffer for `LiveMetalTerrainOverlay` to
    /// encode into and present -- keeps `commandQueue` itself private to this type.
    func makeCommandBuffer() -> MTLCommandBuffer? {
        commandQueue.makeCommandBuffer()
    }

    /// v1.6.0 (#25) increment 6: renders terrain tiles directly into an existing drawable
    /// texture -- no offscreen-texture-then-`CIImage`-then-`CGImage` round trip, unlike
    /// `draw(_:ctx:dirtyRect:)` above (that round trip exists purely to composite into a
    /// `CGContext`, which the live floating overlay bypasses entirely). Reuses the already-
    /// uploaded tiles texture and this renderer's pipeline/sampler.
    ///
    /// `visibleRect` is in `GameRenderView`'s own point space (`NSView.visibleRect`, i.e.
    /// unaffected by `NSScrollView` magnification -- the scroll view's layer transform is what
    /// makes zoom visually work for the CPU path, but this overlay is a *floating* subview,
    /// deliberately exempt from that transform, so it has to account for zoom itself). `scale`
    /// (target-texture pixels per point) folds together both the live magnification and the
    /// display's own backing scale factor in one ratio, since `targetTexture`'s pixel
    /// dimensions are already in real device pixels.
    func renderLiveTerrain(
        tileGrid: TileGrid, visibleRect: NSRect, into targetTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer, tilesImage: CGImage
    ) {
        guard let sheetTexture = texture(for: tilesImage), visibleRect.width > 0, visibleRect.height > 0,
            let range = Self.tileRange(for: visibleRect)
        else { return }

        let scale = Float(targetTexture.width) / Float(visibleRect.width)
        let scaledTileSize = Self.tileSizePixels * scale
        let originXPixels = Float(visibleRect.origin.x) * scale
        let originYPixels = Float(visibleRect.origin.y) * scale

        var instances: [TileInstance] = []
        instances.reserveCapacity((range.maxX - range.minX + 1) * (range.maxY - range.minY + 1) * 2)
        for y in range.minY...range.maxY {
            for x in range.minX...range.maxX {
                let origin = SIMD2<Float>(
                    Float(x) * scaledTileSize - originXPixels, Float(y) * scaledTileSize - originYPixels
                )
                let index = unseenTileAsSeaImage(mapimage(tileGrid, Int32(x), Int32(y)))
                instances.append(TileInstance(origin: origin, uvOrigin: Self.uvOrigin(forIndex: index)))
                if isMinedTile(tileGrid, Int32(x), Int32(y)) != 0 {
                    instances.append(TileInstance(origin: origin, uvOrigin: Self.uvOrigin(forIndex: MINE00IMAGE)))
                }
            }
        }
        guard !instances.isEmpty,
            let instanceBuffer = device.makeBuffer(
                bytes: instances, length: instances.count * MemoryLayout<TileInstance>.stride, options: []
            )
        else { return }

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = targetTexture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        passDescriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
        var targetSize = SIMD2<Float>(Float(targetTexture.width), Float(targetTexture.height))
        encoder.setVertexBytes(&targetSize, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        var tileSizeForDraw = scaledTileSize
        encoder.setVertexBytes(&tileSizeForDraw, length: MemoryLayout<Float>.size, index: 2)
        var uvCellSize = 1.0 / Self.sheetCellsPerAxis
        encoder.setVertexBytes(&uvCellSize, length: MemoryLayout<Float>.size, index: 3)
        encoder.setFragmentTexture(sheetTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instances.count)
        encoder.endEncoding()
    }

    private func renderInstances(
        _ instances: [TileInstance], sheetTexture: MTLTexture, targetWidth: Float, targetHeight: Float
    ) -> CGImage? {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: max(1, Int(targetWidth)), height: max(1, Int(targetHeight)),
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        guard let targetTexture = device.makeTexture(descriptor: textureDescriptor),
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let instanceBuffer = device.makeBuffer(
                bytes: instances, length: instances.count * MemoryLayout<TileInstance>.stride, options: []
            )
        else { return nil }

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = targetTexture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        passDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return nil }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
        var targetSize = SIMD2<Float>(targetWidth, targetHeight)
        encoder.setVertexBytes(&targetSize, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        var tileSizePixels = Self.tileSizePixels
        encoder.setVertexBytes(&tileSizePixels, length: MemoryLayout<Float>.size, index: 2)
        var uvCellSize = 1.0 / Self.sheetCellsPerAxis
        encoder.setVertexBytes(&uvCellSize, length: MemoryLayout<Float>.size, index: 3)
        encoder.setFragmentTexture(sheetTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instances.count)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard let ciImage = CIImage(mtlTexture: targetTexture, options: [.colorSpace: NSNull()]) else { return nil }
        // `CIImage(mtlTexture:)` reads a Metal texture bottom-left-origin (its own GL-heritage
        // default, distinct from `MTKTextureLoader`'s configurable `.origin`) -- flip vertically
        // so the resulting `CGImage` is top-left-origin, matching every other image this app
        // hands to `blit(_:in:_:)`.
        let flipped = ciImage.transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(targetHeight)))
        return ciContext.createCGImage(flipped, from: CGRect(x: 0, y: 0, width: CGFloat(targetWidth), height: CGFloat(targetHeight)))
    }
}
