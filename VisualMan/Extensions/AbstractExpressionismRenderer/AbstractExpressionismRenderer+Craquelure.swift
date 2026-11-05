//
//  AbstractExpressionismRenderer+Craquelure.swift
//  VisualMan
//
//  Created on 11/2/26.
//

#if !targetEnvironment(simulator)
import Metal
import os
import simd

extension AbstractExpressionismRenderer {
  nonisolated static let crackTileSize = 512
  nonisolated static let crackPrimaryCells = 17
  nonisolated static let crackSecondaryCells = 40

  nonisolated static func makeCrackPixels() -> [UInt8] {
    let size = crackTileSize
    var pixels = [UInt8](repeating: 0, count: size * size * 2)
    let primary = periodicWorleyEdges(size: size, cells: crackPrimaryCells, seed: 17)
    let secondary = periodicWorleyEdges(size: size, cells: crackSecondaryCells, seed: 41)
    for i in 0..<(size * size) {
      pixels[i * 2]     = UInt8(min(255, Int(primary[i] * 2 * 255)))
      pixels[i * 2 + 1] = UInt8(min(255, Int(secondary[i] * 2 * 255)))
    }
    return pixels
  }

  static func makeCrackTexture(device: MTLDevice, pixels: [UInt8]) -> MTLTexture? {
    let size = crackTileSize
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rg8Unorm, width: size, height: size, mipmapped: false)
    desc.usage = .shaderRead
    desc.storageMode = .shared
    guard let texture = device.makeTexture(descriptor: desc) else {
      logger.error("Could not create the craquelure texture")
      return nil
    }
    pixels.withUnsafeBytes { buf in
      texture.replace(region: MTLRegionMake2D(0, 0, size, size),
                      mipmapLevel: 0,
                      withBytes: buf.baseAddress!,
                      bytesPerRow: size * 2)
    }
    return texture
  }

  nonisolated private static func periodicWorleyEdges(size: Int, cells: Int, seed: Float) -> [Float] {
    func hash(_ x: Int, _ y: Int) -> SIMD2<Float> {
      var h = sin(Float(x) * 127.1 + Float(y) * 311.7 + seed) * 43758.5453
      let a = h - h.rounded(.down)
      h = sin(Float(x) * 269.5 + Float(y) * 183.3 + seed * 1.7) * 43758.5453
      let b = h - h.rounded(.down)
      return SIMD2(a, b)
    }
    var points = [SIMD2<Float>](repeating: .zero, count: cells * cells)
    for cy in 0..<cells {
      for cx in 0..<cells {
        points[cy * cells + cx] = SIMD2(Float(cx), Float(cy))
          + 0.5 + 0.8 * (hash(cx, cy) - 0.5)
      }
    }
    var out = [Float](repeating: 0, count: size * size)
    let scale = Float(cells) / Float(size)
    for py in 0..<size {
      for px in 0..<size {
        let p = SIMD2(Float(px) + 0.5, Float(py) + 0.5) * scale
        let ix = Int(p.x), iy = Int(p.y)
        var f1: Float = 8, f2: Float = 8
        for dy in -1...1 {
          for dx in -1...1 {
            let cx = ((ix + dx) % cells + cells) % cells
            let cy = ((iy + dy) % cells + cells) % cells
            var fp = points[cy * cells + cx]
            if ix + dx < 0 { fp.x -= Float(cells) } else if ix + dx >= cells { fp.x += Float(cells) }
            if iy + dy < 0 { fp.y -= Float(cells) } else if iy + dy >= cells { fp.y += Float(cells) }
            let d = simd_length(fp - p)
            if d < f1 { f2 = f1; f1 = d } else if d < f2 { f2 = d }
          }
        }
        out[py * size + px] = f2 - f1
      }
    }
    return out
  }
}

#endif
