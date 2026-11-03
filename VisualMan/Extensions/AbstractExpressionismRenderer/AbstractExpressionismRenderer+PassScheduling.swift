//
//  AbstractExpressionismRenderer+PassScheduling.swift
//  VisualMan
//
//  Created on 11/3/26.
//

#if !targetEnvironment(simulator)
import Metal
import simd

extension AbstractExpressionismRenderer {
  func runPendingResample(encoder: any MTL4ComputeCommandEncoder, tex: PingPongTextures) {
    guard pendingResample,
          let cSrc = resampleColorSrc, let hwSrc = resampleHeightWetSrc,
          let dSrc = resampleDryColorSrc, let sSrc = resampleSubstrateSrc else { return }
    renderResample(encoder: encoder,
                   colorSrc: cSrc, colorDst: tex.colorIn,
                   hwSrc: hwSrc, hwDst: tex.hwIn,
                   drySrc: dSrc, dryDst: tex.dryColorIn,
                   subSrc: sSrc, subDst: tex.substrateIn,
                   velDst: tex.velocityIn)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    for t in [cSrc, hwSrc, dSrc, sSrc] {
      pendingTextureReleases.append((frame: frameNumber, texture: t))
    }
    resampleColorSrc = nil; resampleHeightWetSrc = nil
    resampleDryColorSrc = nil; resampleSubstrateSrc = nil
    pendingResample = false
    fullCanvasFramesRemaining = 2
  }

  func shouldSkipPaint(split strokesThisFrame: SplitStrokes,
                       fullCanvas: Bool, isClearing: Bool) -> Bool {
    guard !lastFrameSkippedPaint,
          !fullCanvas, !isClearing, !isFirstFrame, !pendingResample,
          strokesThisFrame.isEmpty,
          animatingStrokes.isEmpty,
          framesSinceSmear > 12 else { return false }
    return dt + skippedPaintDt < 0.05
  }

  func encodeComposeOnly(encoder: any MTL4ComputeCommandEncoder,
                         tex: PingPongTextures, params: AbExParams) {
    skippedPaintDt += dt
    framesSinceSmear += 1
    recordSmearBounds([])
    renderCompose(encoder: encoder,
                  color: tex.colorIn, heightWet: tex.hwIn,
                  dryColor: tex.dryColorIn, substrate: tex.substrateIn,
                  output: tex.display, params: params)
  }

  static let smearDirtyFrames = 14
  static let smearRegionPad: Float = 0.04
  static let smearReadMargin: Float = 0.05

  func recordSmearBounds(_ strokes: [AbExStroke]) {
    let bounds = strokes.map(strokeAabb).reduce(SIMD4<Float>(1, 0, 1, 0)) { acc, b in
      SIMD4(min(acc.x, b.x), max(acc.y, b.y), min(acc.z, b.z), max(acc.w, b.w))
    }
    smearDirtyHistory.append(bounds)
    if smearDirtyHistory.count > Self.smearDirtyFrames {
      smearDirtyHistory.removeFirst(smearDirtyHistory.count - Self.smearDirtyFrames)
    }
  }

  private func smearBoundsUV() -> SIMD4<Float>? {
    var u = SIMD4<Float>(1, 0, 1, 0)
    for b in smearDirtyHistory where b.x < b.y {
      u = SIMD4(min(u.x, b.x), max(u.y, b.y), min(u.z, b.z), max(u.w, b.w))
    }
    return (u.x < u.y && u.z < u.w) ? u : nil
  }

  private func pixelRegion(_ u: SIMD4<Float>, pad: Float,
                           clip: CanvasRegion) -> CanvasRegion? {
    let size = Float(canvasSize)
    var x0 = Int(((u.x - pad) * size).rounded(.down))
    var x1 = Int(((u.y + pad) * size).rounded(.up))
    var y0 = Int(((u.z - pad) * size).rounded(.down))
    var y1 = Int(((u.w + pad) * size).rounded(.up))
    x0 = max(clip.x, x0 - (x0 & 1)); y0 = max(clip.y, y0 - (y0 & 1))
    x1 = min(clip.x + clip.width, x1 + (x1 & 1))
    y1 = min(clip.y + clip.height, y1 + (y1 & 1))
    guard x1 > x0, y1 > y0 else { return nil }
    return CanvasRegion(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }

  func smearPassRegion(within region: CanvasRegion) -> CanvasRegion? {
    guard let u = smearBoundsUV() else { return nil }
    return pixelRegion(u, pad: Self.smearRegionPad, clip: region)
  }

  func copyForSmearPass(encoder: any MTL4ComputeCommandEncoder,
                        tex: PingPongTextures, region: CanvasRegion) {
    guard let u = smearBoundsUV() else { return }
    let whole = CanvasRegion(x: 0, y: 0, width: canvasSize, height: canvasSize)
    guard let copy = pixelRegion(u, pad: Self.smearRegionPad + Self.smearReadMargin,
                                 clip: whole) else { return }
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .blit)
    func copyRect(_ src: MTLTexture, _ dst: MTLTexture, _ r: CanvasRegion) {
      let w = min(r.width, src.width - r.x), h = min(r.height, src.height - r.y)
      guard w > 0, h > 0 else { return }
      let origin = MTLOrigin(x: r.x, y: r.y, z: 0)
      encoder.copy(sourceTexture: src, sourceSlice: 0, sourceLevel: 0,
                   sourceOrigin: origin, sourceSize: MTLSize(width: w, height: h, depth: 1),
                   destinationTexture: dst, destinationSlice: 0, destinationLevel: 0,
                   destinationOrigin: origin)
    }
    copyRect(tex.colorOut, tex.colorMid, copy)
    copyRect(tex.hwOut, tex.hwMid, copy.halved)
    copyRect(tex.dryColorOut, tex.dryColorMid, copy.halved)
    encoder.barrier(afterEncoderStages: .blit, beforeEncoderStages: .dispatch)
  }
}

#endif
