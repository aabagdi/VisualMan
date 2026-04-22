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

  struct WarmUpTextures {
    let simA: MTLTexture
    let simB: MTLTexture
    let display: MTLTexture
  }

  func makeWarmUpTextures() -> WarmUpTextures? {
    let simDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rg8Unorm,
      width: 64,
      height: 64,
      mipmapped: false
    )
    simDesc.usage = [.shaderRead, .shaderWrite]
    simDesc.storageMode = .shared

    let displayDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm,
      width: 256,
      height: 256,
      mipmapped: false
    )
    displayDesc.usage = [.shaderRead, .shaderWrite]
    displayDesc.storageMode = .private

    guard let dummySimA = device.makeTexture(descriptor: simDesc),
          let dummySimB = device.makeTexture(descriptor: simDesc),
          let dummyDisplay = device.makeTexture(descriptor: displayDesc) else {
      return nil
    }
    return WarmUpTextures(simA: dummySimA, simB: dummySimB, display: dummyDisplay)
  }

  func encodeWarmUpPasses(encoder: some MTL4ComputeCommandEncoder, textures: WarmUpTextures) {
    let params = GameOfLifeParams(
      bass: 0, mid: 0, high: 0, time: 0,
      simWidth: 64, simHeight: 64,
      frameCount: 0, spawnRate: 0
    )

    encoder.setComputePipelineState(stepPipeline)
    argumentTable.setTexture(textures.simA.gpuResourceID, index: 0)
    argumentTable.setTexture(textures.simB.gpuResourceID, index: 1)
    argumentTable.setAddress(writeUniform(params), index: 0)
    let simTG = MTLSize(width: 16, height: 16, depth: 1)
    let simGroups = MTLSize(width: 4, height: 4, depth: 1)
    encoder.dispatchThreadgroups(threadgroupsPerGrid: simGroups, threadsPerThreadgroup: simTG)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(renderPipeline)
    argumentTable.setTexture(textures.simB.gpuResourceID, index: 0)
    argumentTable.setTexture(textures.display.gpuResourceID, index: 1)
    argumentTable.setAddress(writeUniform(params), index: 0)
    let renderTG = MTLSize(width: 16, height: 16, depth: 1)
    let renderGroups = MTLSize(width: 16, height: 16, depth: 1)
    encoder.dispatchThreadgroups(threadgroupsPerGrid: renderGroups, threadsPerThreadgroup: renderTG)
  }

  func seedInitialState() {
    guard let simA else { return }
    if frameNumber > 0 {
      sharedEvent.wait(untilSignaledValue: frameNumber, timeoutMS: 200)
    }
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
