//
//  AbstractExpressionismRenderer+TileCulling.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/29/26.
//

#if !targetEnvironment(simulator)
import Foundation
import simd

extension AbstractExpressionismRenderer {
  static let tileGridDim: Int = 16
  static let tileGridCount: Int = tileGridDim * tileGridDim
  static let maxStrokesPerTile: Int = 8

  struct TileMap {
    var counts: [UInt32]
    var indices: [UInt32]

    static var empty: TileMap {
      TileMap(
        counts: [UInt32](repeating: 0, count: tileGridCount),
        indices: [UInt32](repeating: 0,
                          count: tileGridCount * maxStrokesPerTile))
    }
  }

  func strokeAabb(_ s: AbExStroke) -> SIMD4<Float> {
    let center = SIMD2<Float>(s.posAngle.x, s.posAngle.y)
    let angle = s.posAngle.z
    let dir = SIMD2<Float>(cos(angle), sin(angle))

    var alongOffset: Float = 0
    var halfAlong: Float
    var halfAcross: Float

    switch Int(s.sizeOpacity.w) {
    case 1:
      halfAlong = max(s.posAngle.w, 0.01) * 1.8
      halfAcross = max(s.sizeOpacity.x, 0.01) * 1.8
    case 2:
      let radius = max(s.posAngle.w, 0.002) * 1.6
      let isElongated = Int(floor(s.color.w)) == 1
      halfAlong = isElongated ? radius / 0.22 : radius
      halfAcross = radius
    case 3:
      let dripLen = max(s.posAngle.w, 0.02)
      let topWidth = max(s.sizeOpacity.x, 0.003)
      alongOffset = dripLen * 0.5
      halfAlong = dripLen * 0.54
      halfAcross = dripLen * 0.13 + topWidth * 2.0
    case 5:
      halfAlong = max(s.posAngle.w, 0.01) * 1.05
      halfAcross = max(s.sizeOpacity.x, 0.01) * 1.05
    case 6:
      let halfLen = max(s.posAngle.w, 0.01)
      let halfWd = max(s.sizeOpacity.x, 0.001)
      halfAlong = halfLen * 1.05
      halfAcross = halfWd * 3.7 + abs(s.animation.w) * halfLen * 0.35
    default:
      let halfLen = max(s.posAngle.w, 0.01)
      let halfWd = max(s.sizeOpacity.x, 0.002)
      let w_curve = s.animation.w
      let amp: Float = abs(w_curve) >= 1.0
        ? sign(w_curve) * (abs(w_curve) - 1.0)
        : w_curve
      halfAlong = halfLen * 1.30
      halfAcross = halfWd * 1.5 + abs(amp) * halfLen * 0.5
    }

    let boxCenter = center + dir * alongOffset
    let cs = abs(dir.x)
    let sn = abs(dir.y)
    let aabbHalfX = halfAlong * cs + halfAcross * sn
    let aabbHalfY = halfAlong * sn + halfAcross * cs

    let minU = (boxCenter.x - aabbHalfX) + 0.5
    let maxU = (boxCenter.x + aabbHalfX) + 0.5
    let minV = (boxCenter.y - aabbHalfY) + 0.5
    let maxV = (boxCenter.y + aabbHalfY) + 0.5
    return SIMD4(minU, maxU, minV, maxV)
  }

  func buildTileMap(strokes: [AbExStroke]) -> TileMap {
    var map = TileMap.empty
    if strokes.isEmpty { return map }

    let dim = Self.tileGridDim
    let dimF = Float(dim)
    let cap = Self.maxStrokesPerTile

    let dimMax = dim - 1

    for (idx, s) in strokes.enumerated() {
      if idx >= 65535 { break }
      let bb = strokeAabb(s)

      let minTileX = max(0, min(dimMax, Int(floor(bb.x * dimF))))
      let maxTileX = max(0, min(dimMax, Int(floor(bb.y * dimF))))
      let minTileY = max(0, min(dimMax, Int(floor(bb.z * dimF))))
      let maxTileY = max(0, min(dimMax, Int(floor(bb.w * dimF))))

      if bb.y < 0 || bb.x > 1 || bb.w < 0 || bb.z > 1 { continue }

      let strokeIdx = UInt32(idx)
      for ty in minTileY...maxTileY {
        for tx in minTileX...maxTileX {
          let tileIdx = ty * dim + tx
          let count = Int(map.counts[tileIdx])
          if count < cap {
            map.indices[tileIdx * cap + count] = strokeIdx
            map.counts[tileIdx] = UInt32(count + 1)
          }
        }
      }
    }

    return map
  }

  struct CanvasRegion {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    var origin: SIMD2<UInt32> { SIMD2(UInt32(x), UInt32(y)) }
    var halved: CanvasRegion {
      CanvasRegion(x: x / 2, y: y / 2, width: width / 2, height: height / 2)
    }
  }

  func paintRegion(full: Bool,
                   strokes: [AbExStroke]) -> (CanvasRegion, [AbExStroke]) {
    let size = canvasSize
    let whole = CanvasRegion(x: 0, y: 0, width: size, height: size)
    guard Self.cullHiddenCanvas, !full,
          lastDisplayWidth > 0, lastDisplayHeight > 0 else { return (whole, strokes) }

    let dw = Float(lastDisplayWidth), dh = Float(lastDisplayHeight)
    let coverScale = dw >= dh ? SIMD2<Float>(1, dh / dw) : SIMD2<Float>(dw / dh, 1)
    let margin: Float = 0.012 + 0.02
    let halfExtent = 0.5 * coverScale / Self.cameraMinZoom + Self.cameraMaxPan + margin

    let visible = SIMD4<Float>(0.5 - halfExtent.x, 0.5 + halfExtent.x,
                               0.5 - halfExtent.y, 0.5 + halfExtent.y)
    var paintRect = visible
    var kept: [AbExStroke] = []
    kept.reserveCapacity(strokes.count)
    for stroke in strokes {
      let bb = strokeAabb(stroke)
      let touchesVisible = bb.x < visible.y && bb.y > visible.x
                        && bb.z < visible.w && bb.w > visible.z
      guard touchesVisible else { continue }
      kept.append(stroke)
      paintRect = SIMD4(min(paintRect.x, bb.x - margin), max(paintRect.y, bb.y + margin),
                        min(paintRect.z, bb.z - margin), max(paintRect.w, bb.w + margin))
    }

    func span(_ lo: Float, _ hi: Float) -> (Int, Int) {
      var x0 = Int((max(0, lo) * Float(size)).rounded(.down))
      var x1 = Int((min(1, hi) * Float(size)).rounded(.up))
      x0 = max(0, x0 - (x0 & 1))
      x1 = min(size, x1 + (x1 & 1))
      return (x0, max(x0, x1))
    }
    let (x0, x1) = span(paintRect.x, paintRect.y)
    let (y0, y1) = span(paintRect.z, paintRect.w)
    return (CanvasRegion(x: x0, y: y0, width: x1 - x0, height: y1 - y0), kept)
  }
}

#endif
