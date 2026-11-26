//
//  AbstractExpressionismRenderer+BakedNoise.swift
//  VisualMan
//
//  Created on 11/26/26.
//

#if !targetEnvironment(simulator)
import Metal

extension AbstractExpressionismRenderer {
  static let noiseFieldScale = 4

  func rebuildNoiseTextures(size: Int) -> Bool {
    for old in [grainNoiseTexture, fieldNoiseTexture] {
      if let t = old { pendingTextureReleases.append((frame: frameNumber, texture: t)) }
    }
    grainNoiseTexture = nil
    fieldNoiseTexture = nil

    let fieldSize = (size + Self.noiseFieldScale - 1) / Self.noiseFieldScale
    let grainDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Snorm, width: size, height: size, mipmapped: false)
    let fieldDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float, width: fieldSize, height: fieldSize, mipmapped: false)
    for desc in [grainDesc, fieldDesc] {
      desc.usage = [.shaderRead, .shaderWrite]
      desc.storageMode = .private
    }
    guard let grain = device.makeTexture(descriptor: grainDesc),
          let field = device.makeTexture(descriptor: fieldDesc) else { return false }

    residencySet.addAllocation(grain)
    residencySet.addAllocation(field)
    grainNoiseTexture = grain
    fieldNoiseTexture = field
    noiseBakePending = true
    return true
  }

  func bakeNoiseIfNeeded(encoder: any MTL4ComputeCommandEncoder) {
    guard noiseBakePending, let grain = grainNoiseTexture, let field = fieldNoiseTexture else { return }
    noiseBakePending = false
    encoder.setComputePipelineState(noiseBakePipeline)
    argumentTable.setTexture(grain.gpuResourceID, index: 0)
    argumentTable.setTexture(field.gpuResourceID, index: 1)
    dispatch(encoder: encoder, pipeline: noiseBakePipeline, width: grain.width, height: grain.height)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
  }
}

#endif
