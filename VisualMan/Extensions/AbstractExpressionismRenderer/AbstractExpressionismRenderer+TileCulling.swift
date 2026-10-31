//
//  AbstractExpressionismRenderer+TileCulling.swift
//  VisualMan
//
//  Created by on 4/29/26.
//
//  Tile-based stroke culling. Each frame, strokes are bucketed into a
//  16×16 tile grid in canvas-uv space [-0.5..0.5]. The Metal kernels then
//  read the per-tile stroke list (an indirection: count + indices into the
//  full strokes buffer) instead of looping over every stroke for every
//  pixel.
//
//  Without culling, every pixel does ~20 ALU ops per stroke just to
//  reject it on the bounding box. With ~12 strokes per frame and 6.9M
//  pixels, that's 1.4 GFLOPs of pure rejection work per pass. After
//  culling, average strokes-per-tile drops to 1-3 and the rejection
//  work drops by 4-8×.
//
//  CPU cost is trivial - 12 strokes × 16x16 tile checks = ~3000 ops per
//  frame, lost in the noise.
//

#if !targetEnvironment(simulator)
import Foundation
import simd

extension AbstractExpressionismRenderer {
  static let tileGridDim: Int = 16
  static let tileGridCount: Int = tileGridDim * tileGridDim
  // Reduced from 12 to 8 - with the new lower stroke generation rates,
  // most tiles only see 0-3 strokes per frame anyway. Capping at 8
  // protects against pathological density spikes (e.g. multiple Pollock
  // trails crossing in the same tile) without losing useful strokes
  // in normal operation. Saves up to 33% of inner-loop work in worst
  // case.
  static let maxStrokesPerTile: Int = 8

  struct TileMap {
    var counts: [UInt32]    // length tileGridCount
    var indices: [UInt32]   // length tileGridCount * maxStrokesPerTile

    static var empty: TileMap {
      TileMap(
        counts: [UInt32](repeating: 0, count: tileGridCount),
        indices: [UInt32](repeating: 0,
                          count: tileGridCount * maxStrokesPerTile))
    }
  }

  /// Compute the conservative axis-aligned bounding box (in canvas-uv
  /// coords [-0.5..0.5]) of a stroke. Each stroke type gets the extent its
  /// shader function can actually touch (its early-out limits), because the
  /// types pack their geometry differently: a splatter's sizeOpacity.x is a
  /// type roll, not a width, and drips hang from their top point rather than
  /// being centred on it.
  ///
  /// The bbox is intentionally a slight overestimate. False positives
  /// (tile contains stroke index but stroke doesn't actually paint there)
  /// cost a kernel iteration with early-out; false negatives (stroke
  /// missing from tile that should have it) produce visible holes. Always
  /// err toward false positives.
  ///
  /// Returns (minU, maxU, minV, maxV) in normalized [0..1] uv space.
  func strokeAabb(_ s: AbExStroke) -> SIMD4<Float> {
    let center = SIMD2<Float>(s.posAngle.x, s.posAngle.y)
    let angle = s.posAngle.z
    let dir = SIMD2<Float>(cos(angle), sin(angle))

    // Stroke-local box: offset of its centre along `dir`, and half-extents.
    var alongOffset: Float = 0
    var halfAlong: Float
    var halfAcross: Float

    switch Int(s.sizeOpacity.w) {
    case 1:
      // Wash: evaluateWash rejects at radius 1.8 in (halfLen, halfWd) space.
      halfAlong = max(s.posAngle.w, 0.01) * 1.8
      halfAcross = max(s.sizeOpacity.x, 0.01) * 1.8
    case 2:
      // Splatter: posAngle.w is the radius; rejection at 1.6 × radius.
      // Shape 1 is stretched along its angle (local x scaled by 0.22).
      let radius = max(s.posAngle.w, 0.002) * 1.6
      let isElongated = Int(floor(s.color.w)) == 1
      halfAlong = isElongated ? radius / 0.22 : radius
      halfAcross = radius
    case 3:
      // Drip: hangs from its top point over [-0.04, 1.04] × length, with
      // lateral wobble bounded by evaluateDrip's maxOffset.
      let dripLen = max(s.posAngle.w, 0.02)
      let topWidth = max(s.sizeOpacity.x, 0.003)
      alongOffset = dripLen * 0.5
      halfAlong = dripLen * 0.54
      halfAcross = dripLen * 0.13 + topWidth * 2.0
    case 5:
      // Scumble: elliptical, rejection at radius 1.05.
      halfAlong = max(s.posAngle.w, 0.01) * 1.05
      halfAcross = max(s.sizeOpacity.x, 0.01) * 1.05
    case 6:
      // Line: 1.05 × halfLen along; across allows 3 × width after removing
      // the bend (curvature · halfLen · 0.35) and wobble (≤ 0.7 × width).
      let halfLen = max(s.posAngle.w, 0.01)
      let halfWd = max(s.sizeOpacity.x, 0.001)
      halfAlong = halfLen * 1.05
      halfAcross = halfWd * 3.7 + abs(s.animation.w) * halfLen * 0.35
    default:
      // Gestural (0) and knife (4). 1.30 along / 1.5 across match the
      // velocity-deposit zone, which shares this tile map, plus the C/S
      // curve bulge. animation.w packs C/S: |w|<1 = C with amp=w,
      // |w|>=1 = S with amp = sign(w)·(|w|-1); max offset |amp|·halfLen·0.5.
      let halfLen = max(s.posAngle.w, 0.01)
      let halfWd = max(s.sizeOpacity.x, 0.002)
      let w_curve = s.animation.w
      let amp: Float = abs(w_curve) >= 1.0
        ? sign(w_curve) * (abs(w_curve) - 1.0)
        : w_curve
      halfAlong = halfLen * 1.30
      halfAcross = halfWd * 1.5 + abs(amp) * halfLen * 0.5
    }

    // Rotated rectangle AABB: |cos|·alongHalf + |sin|·acrossHalf, etc.
    let boxCenter = center + dir * alongOffset
    let cs = abs(dir.x)
    let sn = abs(dir.y)
    let aabbHalfX = halfAlong * cs + halfAcross * sn
    let aabbHalfY = halfAlong * sn + halfAcross * cs

    // Shift from [-0.5..0.5] to [0..1] uv
    let minU = (boxCenter.x - aabbHalfX) + 0.5
    let maxU = (boxCenter.x + aabbHalfX) + 0.5
    let minV = (boxCenter.y - aabbHalfY) + 0.5
    let maxV = (boxCenter.y + aabbHalfY) + 0.5
    return SIMD4(minU, maxU, minV, maxV)
  }

  /// Bucket a stroke array into a 16×16 tile grid. Each tile gets a list
  /// of stroke indices whose bbox overlaps that tile.
  ///
  /// Strokes outside the canvas (bbox entirely off the [0..1] uv square)
  /// contribute nothing. Strokes that overflow a tile's capacity
  /// (maxStrokesPerTile already in tile) are silently dropped from that
  /// tile, but since maxStrokesPerTile is close to the per-frame stroke cap
  /// this only happens when nearly all strokes overlap one tile - extremely
  /// unlikely with our spatial distribution.
  func buildTileMap(strokes: [AbExStroke]) -> TileMap {
    var map = TileMap.empty
    if strokes.isEmpty { return map }

    let dim = Self.tileGridDim
    let dimF = Float(dim)
    let cap = Self.maxStrokesPerTile

    // Pre-clamp scalar; avoids per-tile branches inside the hot loop.
    let dimMax = dim - 1

    for (idx, s) in strokes.enumerated() {
      if idx >= 65535 { break }  // sanity
      let bb = strokeAabb(s)

      // Convert uv bbox to tile-index range, clamping to [0, dim-1].
      // floor(uv * dim) gives the tile index containing that uv.
      let minTileX = max(0, min(dimMax, Int(floor(bb.x * dimF))))
      let maxTileX = max(0, min(dimMax, Int(floor(bb.y * dimF))))
      let minTileY = max(0, min(dimMax, Int(floor(bb.z * dimF))))
      let maxTileY = max(0, min(dimMax, Int(floor(bb.w * dimF))))

      // Skip if bbox is entirely outside [0..1] uv (can happen for outlier
      // splatters near canvas edges with extreme curvature).
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
