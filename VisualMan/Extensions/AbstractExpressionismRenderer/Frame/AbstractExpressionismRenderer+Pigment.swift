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
  static let pigmentHotFrames: UInt8 = 24
  static let pigmentWarmFrames: UInt8 = 200
  static let pigmentWarmInterval = 4
  static let pigmentBands = 16
  static let pigmentDirtyPad: Float = 0.05
  static let pigmentTileDim = 32

  func pigmentRegions(paintRegion region: CanvasRegion,
                      strokes: [AbExStroke]) -> [CanvasRegion] {
    if isFirstFrame || pigmentFullRefreshFrames > 0 {
      pigmentFullRefreshFrames = max(0, pigmentFullRefreshFrames - 1)
      pigmentDirtyTiles = []
      return [CanvasRegion(x: 0, y: 0, width: canvasSize, height: canvasSize)]
    }

    var regions: [CanvasRegion] = []
    let bands = Self.pigmentBands
    let bandH = (region.height + bands - 1) / bands
    let k = pigmentBandIndex % bands
    pigmentBandIndex &+= 1
    let bandY0 = region.y + k * bandH
    let bandY1 = min(bandY0 + bandH, region.y + region.height)
    if bandY1 > bandY0 {
      regions.append(CanvasRegion(x: region.x, y: bandY0, width: region.width,
                                  height: bandY1 - bandY0))
    }

    markPigmentDirty(strokes)
    for r in dirtyTileRects() {
      let x0 = max(region.x, r.x), x1 = min(region.x + region.width, r.x + r.width)
      let y0 = max(region.y, r.y), y1 = min(region.y + region.height, r.y + r.height)
      guard x1 > x0 else { continue }
      let upperEnd = min(y1, bandY0)
      if upperEnd > y0 {
        regions.append(CanvasRegion(x: x0, y: y0, width: x1 - x0, height: upperEnd - y0))
      }
      let lowerStart = max(y0, bandY1)
      if y1 > lowerStart {
        regions.append(CanvasRegion(x: x0, y: lowerStart, width: x1 - x0, height: y1 - lowerStart))
      }
    }
    return regions
  }

  private func markPigmentDirty(_ strokes: [AbExStroke]) {
    let dim = Self.pigmentTileDim
    if pigmentDirtyTiles.count != dim * dim {
      pigmentDirtyTiles = [UInt8](repeating: 0, count: dim * dim)
    }
    for i in pigmentDirtyTiles.indices where pigmentDirtyTiles[i] > 0 {
      pigmentDirtyTiles[i] -= 1
    }
    for s in strokes {
      strokeBox(s).padded(by: Self.pigmentDirtyPad).forEachTile(dim: dim) { tile in
        pigmentDirtyTiles[tile] = Self.pigmentHotFrames + Self.pigmentWarmFrames
      }
    }
  }

  private func tileNeedsRefresh(x: Int, y: Int) -> Bool {
    let age = pigmentDirtyTiles[y * Self.pigmentTileDim + x]
    if age > Self.pigmentWarmFrames { return true }
    return age > 0 && (pigmentBandIndex + y) % Self.pigmentWarmInterval == 0
  }

  private struct TileRun {
    var x0: Int
    var x1: Int
    var y0: Int
  }

  private func dirtyTileRuns(row ty: Int) -> [TileRun] {
    let dim = Self.pigmentTileDim
    var runs: [TileRun] = []
    var tx = 0
    while tx < dim {
      guard tileNeedsRefresh(x: tx, y: ty) else { tx += 1; continue }
      let start = tx
      while tx < dim, tileNeedsRefresh(x: tx, y: ty) { tx += 1 }
      runs.append(TileRun(x0: start, x1: tx, y0: ty))
    }
    return runs
  }

  private func dirtyTileRects() -> [CanvasRegion] {
    let dim = Self.pigmentTileDim
    let size = canvasSize
    var done: [CanvasRegion] = []
    var open: [TileRun] = []
    for ty in 0...dim {
      let runs = ty < dim ? dirtyTileRuns(row: ty) : []
      var next: [TileRun] = []
      for o in open {
        if runs.contains(where: { $0.x0 == o.x0 && $0.x1 == o.x1 }) {
          next.append(o)
        } else {
          let px0 = o.x0 * size / dim, px1 = o.x1 * size / dim
          let py0 = o.y0 * size / dim, py1 = ty * size / dim
          done.append(CanvasRegion(x: px0, y: py0, width: px1 - px0, height: py1 - py0))
        }
      }
      for r in runs where !open.contains(where: { $0.x0 == r.x0 && $0.x1 == r.x1 }) {
        next.append(r)
      }
      open = next
    }
    return done
  }

  func renderPigment(encoder: any MTL4ComputeCommandEncoder,
                     wet: MTLTexture, dry: MTLTexture,
                     heightWet: MTLTexture, substrate: MTLTexture,
                     params: AbExParams, regions: [CanvasRegion]) {
    guard let pig = pigmentTexture, let mat = materialTexture, let shadow = shadowTexture,
          let lut = mixboxLUT, let cracks = crackTexture,
          let grain = grainNoiseTexture, let field = fieldNoiseTexture, !regions.isEmpty else { return }
    encoder.setComputePipelineState(pigmentPipeline)
    argumentTable.setTexture(wet.gpuResourceID, index: 0)
    argumentTable.setTexture(dry.gpuResourceID, index: 1)
    argumentTable.setTexture(pig.gpuResourceID, index: 2)
    argumentTable.setTexture(lut.gpuResourceID, index: 3)
    argumentTable.setTexture(heightWet.gpuResourceID, index: 4)
    argumentTable.setTexture(substrate.gpuResourceID, index: 5)
    argumentTable.setTexture(cracks.gpuResourceID, index: 6)
    argumentTable.setTexture(mat.gpuResourceID, index: 7)
    argumentTable.setTexture(shadow.gpuResourceID, index: 8)
    argumentTable.setTexture(grain.gpuResourceID, index: 9)
    argumentTable.setTexture(field.gpuResourceID, index: 10)
    argumentTable.setAddress(writeUniform(params), index: 0)
    for r in regions where r.width > 0 && r.height > 0 {
      argumentTable.setAddress(writeUniform(r.origin), index: 1)
      dispatch(encoder: encoder, pipeline: pigmentPipeline,
               width: r.width, height: r.height)
    }
  }
}

#endif
