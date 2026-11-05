//
//  LiquidLightRenderer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/7/26.
//

#if !targetEnvironment(simulator)
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
  var flowPhase: Float
  var pad0: Float = 0
  var pad1: Float = 0
  var pad2: Float = 0
  var drops: LiquidLightDrops
  var dropPrecomp: LiquidLightDropPrecomp
  var dropColors: LiquidLightDropColors
}

struct BlurParams {
  var innerRadius: Float
  var outerRadius: Float
  var maxBlurRadius: Float
  var bass: Float
  var mid: Float
}

struct FeedbackParams {
  var dt: Float
  var time: Float
  var bass: Float
  var historyValid: UInt32
}

@MainActor
final class LiquidLightRenderer: MetalVisualizerRenderer {
  let device: MTLDevice
  let commandQueue: any MTL4CommandQueue

  var renderPipeline: MTLComputePipelineState
  var feedbackPipeline: MTLComputePipelineState
  var blurPipeline: MTLComputePipelineState

  var time: Float = 0
  var dt: Float = 1.0 / 60.0
  var lastFrameTime: CFTimeInterval = 0
  var wallClock: Float = 0
  var smoothedSpeed: Float = 0.25
  var flowPhase: Float = 0

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
  var argumentTables: [any MTL4ArgumentTable]
  var uniformBuffers = [MTLBuffer]()
  var uniformOffset: Int = 0
  static let uniformBufferSize: Int = 4096
  let sharedEvent: MTLSharedEvent
  var frameNumber: UInt64 = 0
  let residencySet: MTLResidencySet
  nonisolated static let logger = Logger(subsystem: "com.VisualMan", category: "LiquidLightRenderer")

  var currentUniformBuffer: MTLBuffer

  static let renderScale: Float = 0.75

  private var intermediateTexture: MTLTexture?
  private var historyTextures: [MTLTexture] = []
  private var finalTextures: [MTLTexture] = []
  private var lastDrawableWidth: Int = 0
  private var lastDrawableHeight: Int = 0
  var historyValid: Bool = false

  var resumeSuppressionRemaining: Float = 0

  var resumeFadeIn: Float = 1.0
  static let resumeFadeDuration: Float = 0.8

  private var pendingTextureReleases: [(frame: UInt64, texture: MTLTexture)] = []

  static func create(device: MTLDevice) async -> LiquidLightRenderer? {
    guard let pipelines = await compilePipelines(device: device) else { return nil }
    guard let renderer = LiquidLightRenderer(device: device, pipelines: pipelines) else { return nil }
    renderer.warmUpGPU()
    return renderer
  }

  @concurrent
  nonisolated private static func compilePipelines(device: MTLDevice) async -> Pipelines? {
    guard let compiler = try? device.makeCompiler(descriptor: MTL4CompilerDescriptor()) else {
      return nil
    }
    return createPipelines(device: device, compiler: compiler)
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

    guard let argumentTables = Self.createArgumentTables(device: device) else { return nil }

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
    self.argumentTables = argumentTables
    self.renderPipeline = pipelines.render
    self.feedbackPipeline = pipelines.feedback
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

    let historyDesc = Self.historyTextureDescriptor(width: 256, height: 256)

    guard let dummyA = device.makeTexture(descriptor: desc),
          let dummyB = device.makeTexture(descriptor: desc),
          let dummyHistory = device.makeTexture(descriptor: historyDesc) else { return }
    residencySet.addAllocation(dummyA)
    residencySet.addAllocation(dummyB)
    residencySet.addAllocation(dummyHistory)
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

    renderLiquidLight(encoder: encoder, output: dummyA, audio: .zero)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    renderFeedback(encoder: encoder, render: dummyA, historyIn: dummyHistory,
                   historyOut: dummyHistory, audio: .zero, historyValid: false)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    renderBlur(encoder: encoder, input: dummyHistory, output: dummyB, audio: .zero)

    encoder.endEncoding()
    commandBuffer.endCommandBuffer()
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: warmupFrame)
    frameNumber = warmupFrame

    sharedEvent.wait(untilSignaledValue: warmupFrame, timeoutMS: 1000)
    residencySet.removeAllocation(dummyA)
    residencySet.removeAllocation(dummyB)
    residencySet.removeAllocation(dummyHistory)
    residencySet.commit()
  }

  func prepareForResume() {
    lastFrameTime = 0
    resumeSuppressionRemaining = Self.resumeFadeDuration
    resumeFadeIn = 0
    historyValid = false

    envelope = .zero
    slowEnvelope = .zero
    smoothedBass = 0
    smoothedSpeed = 0.25
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

  private func drainPendingTextureReleases() {
    drainPendingReleases(&pendingTextureReleases)
  }

  private func ensureIntermediateTextures(width: Int, height: Int) -> Bool {
    if width == lastDrawableWidth
        && height == lastDrawableHeight
        && intermediateTexture != nil
        && historyTextures.count == 2
        && finalTextures.count == 2 {
      return true
    }

    if let old = intermediateTexture {
      pendingTextureReleases.append((frame: frameNumber, texture: old))
    }
    for old in historyTextures + finalTextures {
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
    let historyDesc = Self.historyTextureDescriptor(width: width, height: height)

    guard let interTex = device.makeTexture(descriptor: desc),
          let historyA = device.makeTexture(descriptor: historyDesc),
          let historyB = device.makeTexture(descriptor: historyDesc),
          let finalTexA = device.makeTexture(descriptor: desc),
          let finalTexB = device.makeTexture(descriptor: desc) else {
      intermediateTexture = nil
      historyTextures = []
      finalTextures = []
      lastDrawableWidth = 0
      lastDrawableHeight = 0
      return false
    }

    for tex in [interTex, historyA, historyB, finalTexA, finalTexB] {
      residencySet.addAllocation(tex)
    }
    residencySet.commit()

    intermediateTexture = interTex
    historyTextures = [historyA, historyB]
    finalTextures = [finalTexA, finalTexB]
    historyValid = false
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

    let width = max(1, Int((Float(drawableWidth) * Self.renderScale).rounded()))
    let height = max(1, Int((Float(drawableHeight) * Self.renderScale).rounded()))
    guard ensureIntermediateTextures(width: width, height: height),
          let intermediateTex = intermediateTexture else {
      return nil
    }

    guard let encoder = beginFrame() else { return nil }
    let parity = Int(frameNumber & 1)
    let finalTex = finalTextures[parity]
    let historyIn = historyTextures[1 - parity]
    let historyOut = historyTextures[parity]

    renderLiquidLight(encoder: encoder, output: intermediateTex, audio: smoothed)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    renderFeedback(encoder: encoder, render: intermediateTex,
                   historyIn: historyIn, historyOut: historyOut,
                   audio: smoothed, historyValid: historyValid)
    historyValid = true
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    renderBlur(encoder: encoder, input: historyOut, output: finalTex, audio: smoothed)

    encoder.barrier(afterStages: .dispatch, beforeQueueStages: .fragment)
    encoder.endEncoding()

    return finalTex
  }
}

#endif
