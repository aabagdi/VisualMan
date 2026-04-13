//
//  GameOfLifeRenderer+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/12/26.
//

import Metal
import os

extension GameOfLifeRenderer {
  nonisolated static func createPipelines(device: MTLDevice, compiler: any MTL4Compiler) -> Pipelines? {
    guard let library = device.makeDefaultLibrary() else {
      gameOfLifeLogger.error("Failed to create default Metal library")
      return nil
    }

    func makePipeline(_ name: String) -> MTLComputePipelineState? {
      let functionDesc = MTL4LibraryFunctionDescriptor()
      functionDesc.name = name
      functionDesc.library = library
      let pipelineDesc = MTL4ComputePipelineDescriptor()
      pipelineDesc.computeFunctionDescriptor = functionDesc
      do {
        return try compiler.makeComputePipelineState(descriptor: pipelineDesc)
      } catch {
        gameOfLifeLogger.error("Failed to create pipeline '\(name)': \(error.localizedDescription)")
        return nil
      }
    }

    guard let step = makePipeline("gameOfLifeStep"),
          let render = makePipeline("gameOfLifeRender") else {
      return nil
    }
    return Pipelines(step: step, render: render)
  }

  static func createSimTextures(device: MTLDevice, width: Int, height: Int) -> (a: MTLTexture, b: MTLTexture)? {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rg8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .shared

    guard let a = device.makeTexture(descriptor: desc),
          let b = device.makeTexture(descriptor: desc) else {
      return nil
    }
    return (a, b)
  }

  func seedInitialState() {
    guard let simA else { return }
    let w = simWidth
    let h = simHeight
    var pixels = [UInt8](repeating: 0, count: w * h * 2)

    for y in 0..<h {
      for x in 0..<w {
        let idx = (y * w + x) * 2
        let hash = UInt32(truncatingIfNeeded: x) &* 374761393 &+ UInt32(truncatingIfNeeded: y) &* 668265263 &+ 12345
        let rng = Float((hash ^ (hash >> 13)) &* 1274126177 & 0x00FFFFFF) / Float(0x00FFFFFF)
        if rng < 0.25 {
          pixels[idx] = 255
          pixels[idx + 1] = 0
        }
      }
    }

    let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                           size: MTLSize(width: w, height: h, depth: 1))
    simA.replace(region: region, mipmapLevel: 0, withBytes: &pixels, bytesPerRow: w * 2)
  }
}
