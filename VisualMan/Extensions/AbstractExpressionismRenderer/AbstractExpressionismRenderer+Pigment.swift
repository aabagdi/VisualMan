//
//  AbstractExpressionismRenderer+Pigment.swift
//  VisualMan
//
//  Created on 11/2/26.
//

#if !targetEnvironment(simulator)
import Metal
import simd

extension AbstractExpressionismRenderer {
  static let pigmentDirtyFrames = 24
  static let pigmentBands = 8
  static let pigmentDirtyPad: Float = 0.05

  func pigmentRegions(paintRegion region: CanvasRegion,
                      strokes: [AbExStroke]) -> [CanvasRegion] {
    if isFirstFrame || pigmentFullRefreshFrames > 0 {
      pigmentFullRefreshFrames = max(0, pigmentFullRefreshFrames - 1)
      pigmentDirtyHistory.removeAll()
      return [region]
    }

    var regions: [CanvasRegion] = []
    let bands = Self.pigmentBands
    let bandH = (region.height + bands - 1) / bands
    let k = pigmentBandIndex % bands
    pigmentBandIndex &+= 1
    let y0 = region.y + k * bandH
    let h = min(bandH, region.y + region.height - y0)
    if h > 0 {
      regions.append(CanvasRegion(x: region.x, y: y0, width: region.width, height: h))
    }

    if let frameBounds = strokes.map(strokeAabb).reduce(nil, { (acc: SIMD4<Float>?, b) in
      guard let acc else { return b }
      return SIMD4(min(acc.x, b.x), max(acc.y, b.y), min(acc.z, b.z), max(acc.w, b.w))
    }) {
      pigmentDirtyHistory.append(frameBounds)
    } else {
      pigmentDirtyHistory.append(SIMD4(1, 0, 1, 0))
    }
    if pigmentDirtyHistory.count > Self.pigmentDirtyFrames {
      pigmentDirtyHistory.removeFirst(pigmentDirtyHistory.count - Self.pigmentDirtyFrames)
    }
    if let dirty = dirtyRegion(within: region) { regions.append(dirty) }
    return regions
  }

  private func dirtyRegion(within region: CanvasRegion) -> CanvasRegion? {
    var u = SIMD4<Float>(1, 0, 1, 0)
    for b in pigmentDirtyHistory where b.x < b.y {
      u = SIMD4(min(u.x, b.x), max(u.y, b.y), min(u.z, b.z), max(u.w, b.w))
    }
    guard u.x < u.y, u.z < u.w else { return nil }
    let pad = Self.pigmentDirtyPad
    let size = Float(canvasSize)
    let x0 = max(region.x, Int(((u.x - pad) * size).rounded(.down)))
    let x1 = min(region.x + region.width, Int(((u.y + pad) * size).rounded(.up)))
    let y0 = max(region.y, Int(((u.z - pad) * size).rounded(.down)))
    let y1 = min(region.y + region.height, Int(((u.w + pad) * size).rounded(.up)))
    guard x1 > x0, y1 > y0 else { return nil }
    return CanvasRegion(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }

  func renderPigment(encoder: any MTL4ComputeCommandEncoder,
                     wet: MTLTexture, dry: MTLTexture,
                     params: AbExParams, regions: [CanvasRegion]) {
    guard let pig = pigmentTexture, let lut = mixboxLUT, !regions.isEmpty else { return }
    encoder.barrier(afterQueueStages: .dispatch, beforeStages: .dispatch)
    encoder.setComputePipelineState(pigmentPipeline)
    argumentTable.setTexture(wet.gpuResourceID, index: 0)
    argumentTable.setTexture(dry.gpuResourceID, index: 1)
    argumentTable.setTexture(pig.gpuResourceID, index: 2)
    argumentTable.setTexture(lut.gpuResourceID, index: 3)
    argumentTable.setAddress(writeUniform(params), index: 0)
    for r in regions where r.width > 0 && r.height > 0 {
      argumentTable.setAddress(writeUniform(r.origin), index: 1)
      dispatch(encoder: encoder, pipeline: pigmentPipeline,
               width: r.width, height: r.height)
    }
  }
}

#endif
