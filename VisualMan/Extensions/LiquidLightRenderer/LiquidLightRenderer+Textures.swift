//
//  LiquidLightRenderer+Textures.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/5/26.
//

#if !targetEnvironment(simulator)
import Metal
import CoreGraphics

extension LiquidLightRenderer {
  struct FrameTextures {
    let intermediate: MTLTexture
    let history: [MTLTexture]
    let final: [MTLTexture]
    let phase: [MTLTexture]

    var all: [MTLTexture] { [intermediate] + history + final + phase }
  }

  static let outputExtendedRange = true
  static let standardRangePixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
  static let standardRangeColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
  static let outputPixelFormat: MTLPixelFormat = outputExtendedRange ? .rgba16Float : standardRangePixelFormat
  static let outputColorSpace = outputExtendedRange
    ? CGColorSpace(name: CGColorSpace.extendedLinearSRGB) : standardRangeColorSpace

  static func colorTextureDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float,
      width: width,
      height: height,
      mipmapped: false
    )
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private
    return desc
  }

  static func historyTextureDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float,
      width: width,
      height: height,
      mipmapped: false
    )
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private
    return desc
  }

  static func phaseTextureDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
    historyTextureDescriptor(width: width, height: height)
  }

  struct ScratchBuffers {
    let tiles: MTLBuffer
    let lambda: MTLBuffer
    let probe: MTLBuffer
  }

  static func makeScratchBuffers(device: MTLDevice) -> ScratchBuffers? {
    let stride = MemoryLayout<SIMD4<Float>>.stride
    guard let tiles = device.makeBuffer(length: maxReduceTiles * stride, options: .storageModePrivate),
          let lambda = device.makeBuffer(length: stride, options: .storageModePrivate),
          let probe = device.makeBuffer(length: probeCount * stride, options: .storageModeShared) else {
      return nil
    }
    tiles.label = "LiquidLight.reduceTiles"
    lambda.label = "LiquidLight.lambda"
    probe.label = "LiquidLight.probe"
    probe.contents().initializeMemory(as: SIMD4<Float>.self, repeating: SIMD4<Float>(repeating: -1),
                                      count: probeCount)
    return ScratchBuffers(tiles: tiles, lambda: lambda, probe: probe)
  }

  func makeFrameTextures(width: Int, height: Int, simWidth: Int, simHeight: Int) -> FrameTextures? {
    let colorDesc = Self.colorTextureDescriptor(width: width, height: height)
    let historyDesc = Self.historyTextureDescriptor(width: width, height: height)
    let phaseDesc = Self.phaseTextureDescriptor(width: simWidth, height: simHeight)

    guard let intermediate = device.makeTexture(descriptor: colorDesc),
          let historyA = device.makeTexture(descriptor: historyDesc),
          let historyB = device.makeTexture(descriptor: historyDesc),
          let finalA = device.makeTexture(descriptor: colorDesc),
          let finalB = device.makeTexture(descriptor: colorDesc),
          let phaseA = device.makeTexture(descriptor: phaseDesc),
          let phaseB = device.makeTexture(descriptor: phaseDesc) else {
      return nil
    }
    return FrameTextures(intermediate: intermediate,
                         history: [historyA, historyB],
                         final: [finalA, finalB],
                         phase: [phaseA, phaseB])
  }

  func warmUpGPU() {
    let colorDesc = Self.colorTextureDescriptor(width: 256, height: 256)
    let historyDesc = Self.historyTextureDescriptor(width: 256, height: 256)
    let phaseDesc = Self.phaseTextureDescriptor(width: 64, height: 64)

    guard let dummyA = device.makeTexture(descriptor: colorDesc),
          let dummyB = device.makeTexture(descriptor: colorDesc),
          let dummyHistory = device.makeTexture(descriptor: historyDesc),
          let dummyPhaseA = device.makeTexture(descriptor: phaseDesc),
          let dummyPhaseB = device.makeTexture(descriptor: phaseDesc) else { return }
    let dummies = [dummyA, dummyB, dummyHistory, dummyPhaseA, dummyPhaseB]
    for tex in dummies { residencySet.addAllocation(tex) }
    residencySet.commit()

    let warmupFrame: UInt64 = 1
    let frameIndex = Int(warmupFrame % Self.maxFramesInFlight)
    let allocator = commandAllocators[frameIndex]
    currentUniformBuffer = uniformBuffers[frameIndex]
    allocator.reset()
    uniformOffset = 0

    commandBuffer.beginCommandBuffer(allocator: allocator)
    commandBuffer.useResidencySet(residencySet)
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setArgumentTable(argumentTable)

    simWidth = 64
    simHeight = 64
    encodeWarmupPasses(encoder: encoder, color: dummyA, color2: dummyB,
                       history: dummyHistory, phaseA: dummyPhaseA, phaseB: dummyPhaseB)
    encoder.endEncoding()
    commandBuffer.endCommandBuffer()
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: warmupFrame)
    frameNumber = warmupFrame

    sharedEvent.wait(untilSignaledValue: warmupFrame, timeoutMS: 1000)
    for tex in dummies { residencySet.removeAllocation(tex) }
    residencySet.commit()
    simWidth = 0
    simHeight = 0
  }

  private func encodeWarmupPasses(encoder: any MTL4ComputeCommandEncoder,
                                  color: MTLTexture, color2: MTLTexture,
                                  history: MTLTexture,
                                  phaseA: MTLTexture, phaseB: MTLTexture) {
    seedPhase(encoder: encoder, phaseOut: phaseA)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    advectPhase(encoder: encoder, phaseIn: phaseA, phaseOut: phaseB, audio: .zero)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    reduceMassMultiplier(encoder: encoder, phase: phaseB)
    relaxPhase(encoder: encoder, phaseIn: phaseB, phaseOut: phaseA)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    renderLiquidLight(encoder: encoder, output: color, phase: phaseA, audio: .zero)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    renderFeedback(encoder: encoder, render: color, historyIn: history,
                   historyOut: history, audio: .zero, historyValid: false)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    renderBlur(encoder: encoder, input: history, output: color2, audio: .zero)
  }
}

#endif
