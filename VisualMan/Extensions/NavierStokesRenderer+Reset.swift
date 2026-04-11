//
//  NavierStokesRenderer+Reset.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/10/26.
//

import Metal

extension NavierStokesRenderer {
  func reset() {
    time = 0
    prevBass = 0
    prevMid = 0
    renderFrameCount = 0

    guard let blitQueue = device.makeCommandQueue(),
          let cmd = blitQueue.makeCommandBuffer(),
          let blit = cmd.makeBlitCommandEncoder() else {
      return
    }

    let textures: [MTLTexture] = [
      velocityA, pressure, pressureTemp,
      divergenceTexture, dyeA, dyeB, bloomA, bloomB,
      psiA, psiB, u0
    ]

    for tex in textures {
      let region = MTLRegionMake2D(0, 0, tex.width, tex.height)
      let bytesPerPixel = bytesPerPixel(for: tex.pixelFormat)
      let bytesPerRow = bytesPerPixel * tex.width
      let zeros = [UInt8](repeating: 0, count: bytesPerRow * tex.height)

      guard let staging = device.makeBuffer(bytes: zeros,
                                            length: zeros.count,
                                            options: .storageModeShared) else { continue }
      blit.copy(from: staging,
                sourceOffset: 0,
                sourceBytesPerRow: bytesPerRow,
                sourceBytesPerImage: bytesPerRow * tex.height,
                sourceSize: MTLSize(width: tex.width, height: tex.height, depth: 1),
                to: tex,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
      _ = region
    }

    blit.endEncoding()
    cmd.commit()
    cmd.waitUntilCompleted()
    framesSinceReinit = reinitInterval
  }

  private func bytesPerPixel(for format: MTLPixelFormat) -> Int {
    switch format {
    case .r16Float: return 2
    case .rg16Float: return 4
    case .rgba16Float: return 8
    default: return 4
    }
  }
}
