//
//  AbstractExpressionismRenderer+TileCulling.swift
//  VisualMan
//
//  Created by on 4/29/26.
//

import Foundation
import simd

extension AbstractExpressionismRenderer {
  static let tileGridDim: Int = 16
  static let tileGridCount: Int = tileGridDim * tileGridDim
  static let maxStrokesPerTile: Int = 12

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

  private func strokeAabb(_ s: AbExStroke) -> SIMD4<Float> {
    let cx = s.posAngle.x
    let cy = s.posAngle.y
    let angle = s.posAngle.z
    let halfLen = max(s.posAngle.w, 0.01)
    let halfWd = max(s.sizeOpacity.x, 0.002)

    let w_curve = s.animation.w
    let amp: Float = abs(w_curve) >= 1.0
      ? sign(w_curve) * (abs(w_curve) - 1.0)
      : w_curve
    let curveBulge = abs(amp) * halfLen * 0.5

    let effAlong = halfLen * 1.30
    let effAcross = halfWd * 1.5 + curveBulge

    let cs = abs(cos(angle))
    let sn = abs(sin(angle))
    let aabbHalfX = effAlong * cs + effAcross * sn
    let aabbHalfY = effAlong * sn + effAcross * cs

    let minU = (cx - aabbHalfX) + 0.5
    let maxU = (cx + aabbHalfX) + 0.5
    let minV = (cy - aabbHalfY) + 0.5
    let maxV = (cy + aabbHalfY) + 0.5
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
}
