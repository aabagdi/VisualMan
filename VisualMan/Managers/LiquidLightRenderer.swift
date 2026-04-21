//
//  LiquidLightRenderer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/7/26.
//

import Metal
import os
import QuartzCore

struct LiquidLightDrops {
  var d0: SIMD4<Float>
  var d1: SIMD4<Float>
  var d2: SIMD4<Float>
  var d3: SIMD4<Float>
}

struct LiquidLightDropPrecomp {
  var p0: SIMD4<Float>
  var p1: SIMD4<Float>
  var p2: SIMD4<Float>
  var p3: SIMD4<Float>
}

struct LiquidLightDropColors {
  var c0: SIMD4<Float>
  var c1: SIMD4<Float>
  var c2: SIMD4<Float>
  var c3: SIMD4<Float>
}

struct LiquidLightParams {
  var time: Float
  var bass: Float
  var mid: Float
  var high: Float
  var drops: LiquidLightDrops
  var dropPrecomp: LiquidLightDropPrecomp
  var dropColors: LiquidLightDropColors
}

struct BlurParams {
  var innerRadius: Float
  var outerRadius: Float
  var maxBlurRadius: Float
  var texWidth: Float
  var texHeight: Float
  var bass: Float
  var mid: Float
}

@MainActor
final class LiquidLightRenderer: MetalVisualizerRenderer {
  let device: MTLDevice
  let commandQueue: any MTL4CommandQueue

  var renderPipeline: MTLComputePipelineState
  var blurPipeline: MTLComputePipelineState

  var time: Float = 0
  var dt: Float = 1.0 / 60.0
  var lastFrameTime: CFTimeInterval = 0
  var wallClock: Float = 0
  var smoothedSpeed: Float = 0.25

  var envelope: SIMD3<Float> = .zero
  var slowEnvelope: SIMD3<Float> = .zero

  var smoothedBass: Float = 0
  var lastDropWallTime: Float = -10
  var drops: [SIMD4<Float>] = Array(repeating: SIMD4<Float>(0, 0, -1, 0), count: 4)
  var nextDropSlot: Int = 0
  var dropHueCounter: Float = 0

  static let maxFramesInFlight: UInt64 = 3
  var commandAllocators = [any MTL4CommandAllocator]()
  var commandBuffer: any MTL4CommandBuffer
  var argumentTable: any MTL4ArgumentTable
  var uniformBuffers = [MTLBuffer]()
  var uniformOffset: Int = 0
  static let uniformBufferSize: Int = 4096
  let sharedEvent: MTLSharedEvent
  var frameNumber: UInt64 = 0
  let residencySet: MTLResidencySet
  private static let logger = Logger(subsystem: "com.VisualMan", category: "LiquidLightRenderer")

  var currentUniformBuffer: MTLBuffer

  private var intermediateTexture: MTLTexture?
  private var finalTexture: MTLTexture?
  private var lastDrawableWidth: Int = 0
  private var lastDrawableHeight: Int = 0

  var resumeSuppressionRemaining: Float = 0

  var resumeFadeIn: Float = 1.0
  static let resumeFadeDuration: Float = 0.8

  private var pendingTextureReleases: [(frame: UInt64, texture: MTLTexture)] = []

  static func create() async -> LiquidLightRenderer? {
    let prepared = await Task.detached(priority: .userInitiated) {
      guard let device = MTLCreateSystemDefaultDevice(),
            let compiler = try? device.makeCompiler(descriptor: MTL4CompilerDescriptor()) else {
        return nil as (MTLDevice, Pipelines)?
      }
      guard let pipelines = createPipelines(device: device, compiler: compiler) else {
        return nil
      }
      return (device, pipelines)
    }.value

    guard let (device, pipelines) = prepared else { return nil }
    guard let renderer = LiquidLightRenderer(device: device, pipelines: pipelines) else { return nil }
    renderer.warmUpGPU()
    return renderer
  }

  private init?(device: MTLDevice, pipelines: Pipelines) {
    guard let commandQueue = device.makeMTL4CommandQueue(),
          let commandBuffer = device.makeCommandBuffer(),
          let sharedEvent = device.makeSharedEvent() else {
      return nil
    }
    sharedEvent.signaledValue = 0

    guard let allocatorsAndBuffers = Self.createAllocatorsAndBuffers(device: device) else { return nil }
    let commandAllocators = allocatorsAndBuffers.allocators
    let uniformBuffers = allocatorsAndBuffers.buffers
    guard let firstUniformBuffer = uniformBuffers.first else { return nil }

    guard let argumentTable = Self.createArgumentTable(device: device) else { return nil }

    let setDesc = MTLResidencySetDescriptor()
    setDesc.initialCapacity = 4
    guard let residencySet = try? device.makeResidencySet(descriptor: setDesc) else {
      return nil
    }

    self.device = device
    self.commandQueue = commandQueue
    self.commandBuffer = commandBuffer
    self.sharedEvent = sharedEvent
    self.commandAllocators = commandAllocators
    self.uniformBuffers = uniformBuffers
    self.currentUniformBuffer = firstUniformBuffer
    self.argumentTable = argumentTable
    self.renderPipeline = pipelines.render
    self.blurPipeline = pipelines.blur
    self.residencySet = residencySet

    configureResidencySet()
  }

  func warmUpGPU() {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm,
      width: 256,
      height: 256,
      mipmapped: false
    )
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private

    guard let dummyA = device.makeTexture(descriptor: desc),
          let dummyB = device.makeTexture(descriptor: desc) else { return }
    residencySet.addAllocation(dummyA)
    residencySet.addAllocation(dummyB)
    residencySet.commit()
    defer {
      residencySet.removeAllocation(dummyA)
      residencySet.removeAllocation(dummyB)
      residencySet.commit()
    }

    let allocator = commandAllocators[0]
    currentUniformBuffer = uniformBuffers[0]
    allocator.reset()
    uniformOffset = 0

    commandBuffer.beginCommandBuffer(allocator: allocator)
    commandBuffer.useResidencySet(residencySet)
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setArgumentTable(argumentTable)

    renderLiquidLight(encoder: encoder, output: dummyA, audio: .zero)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    renderBlur(encoder: encoder, input: dummyA, output: dummyB, audio: .zero)

    encoder.endEncoding()
    commandBuffer.endCommandBuffer()
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: 1)
    frameNumber = 1
  }

  func prepareForResume() {
    lastFrameTime = 0
    resumeSuppressionRemaining = Self.resumeFadeDuration
    resumeFadeIn = 0

    envelope = .zero
    slowEnvelope = .zero
    smoothedBass = 0
    smoothedSpeed = 0.25
  }

  private func drainPendingTextureReleases() {
    guard !pendingTextureReleases.isEmpty else { return }
    let signaled = sharedEvent.signaledValue
    var removedAny = false
    pendingTextureReleases.removeAll { entry in
      if signaled >= entry.frame {
        residencySet.removeAllocation(entry.texture)
        removedAny = true
        return true
      }
      return false
    }
    if removedAny {
      residencySet.commit()
    }
  }

  private func ensureIntermediateTextures(width: Int, height: Int) -> Bool {
    if width == lastDrawableWidth
        && height == lastDrawableHeight
        && intermediateTexture != nil
        && finalTexture != nil {
      return true
    }

    if let old = intermediateTexture {
      pendingTextureReleases.append((frame: frameNumber, texture: old))
    }
    if let old = finalTexture {
      pendingTextureReleases.append((frame: frameNumber, texture: old))
    }

    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private

    guard let interTex = device.makeTexture(descriptor: desc),
          let finalTex = device.makeTexture(descriptor: desc) else {
      intermediateTexture = nil
      finalTexture = nil
      lastDrawableWidth = 0
      lastDrawableHeight = 0
      return false
    }

    residencySet.addAllocation(interTex)
    residencySet.addAllocation(finalTex)
    residencySet.commit()

    intermediateTexture = interTex
    finalTexture = finalTex
    lastDrawableWidth = width
    lastDrawableHeight = height
    return true
  }

  func encodeFrame(bass: Float,
                   mid: Float,
                   high: Float,
                   drawableWidth: Int,
                   drawableHeight: Int) -> MTLTexture? {
    drainPendingTextureReleases()

    let smoothed = processAudio(bass: bass, mid: mid, high: high)

    guard ensureIntermediateTextures(width: drawableWidth, height: drawableHeight),
          let intermediateTex = intermediateTexture,
          let finalTex = finalTexture else {
      return nil
    }

    guard let encoder = beginFrame() else { return nil }

    renderLiquidLight(encoder: encoder, output: intermediateTex, audio: smoothed)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    renderBlur(encoder: encoder, input: intermediateTex, output: finalTex, audio: smoothed)

    encoder.endEncoding()

    return finalTex
  }
}
