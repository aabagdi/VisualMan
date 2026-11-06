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

@MainActor
final class LiquidLightRenderer: MetalVisualizerRenderer {
  let device: MTLDevice
  let commandQueue: any MTL4CommandQueue

  var seedPipeline: MTLComputePipelineState
  var advectPipeline: MTLComputePipelineState
  var reduceTilesPipeline: MTLComputePipelineState
  var reduceFinalPipeline: MTLComputePipelineState
  var relaxPipeline: MTLComputePipelineState
  var renderPipeline: MTLComputePipelineState
  var feedbackPipeline: MTLComputePipelineState
  var blurPipeline: MTLComputePipelineState

  var time: Float = 0
  var dt: Float = 1.0 / 60.0
  var lastFrameTime: CFTimeInterval = 0
  var wallClock: Float = 0
  var smoothedSpeed: Float = 0.25

  var envelope: SIMD3<Float> = .zero
  var slowEnvelope: SIMD3<Float> = .zero

  var tiltPhase: Float = 0
  var tiltAxis: Float = 0.6
  var lastPressBass: Float = 0

  var smoothedBass: Float = 0
  var lastDropWallTime: Float = -10
  var nextDripWallTime: Float = 1.5
  var drops: [SIMD4<Float>] = Array(repeating: SIMD4<Float>(0, 0, -1, 0), count: 4)
  var dropSizes: [Float] = Array(repeating: 0.05, count: 4)
  var nextDropSlot: Int = 0

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
  static let apertureRadius: Float = 0.40
  static let simScale: Float = 0.3

  static let interfaceEps: Float = 0.775
  static let mobility: Float = 1.0
  static let acMobility: Float = 0.8
  static let relaxStep: Float = 0.02

  static let reduceTileSize = 16
  static let maxReduceTiles = 4096
  let reduceTilesBuffer: MTLBuffer
  let lambdaBuffer: MTLBuffer

  var frameTextures: FrameTextures?
  var lastDrawableWidth: Int = 0
  var lastDrawableHeight: Int = 0
  var historyValid: Bool = false
  var simValid: Bool = false
  var simWidth: Int = 0
  var simHeight: Int = 0

  var resumeSuppressionRemaining: Float = 0

  var resumeFadeIn: Float = 1.0
  static let resumeFadeDuration: Float = 0.8

  var pendingTextureReleases: [(frame: UInt64, texture: MTLTexture)] = []

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
    setDesc.initialCapacity = 10
    guard let residencySet = try? device.makeResidencySet(descriptor: setDesc) else {
      return nil
    }

    let tilesLength = Self.maxReduceTiles * MemoryLayout<SIMD4<Float>>.stride
    guard let reduceTilesBuffer = device.makeBuffer(length: tilesLength, options: .storageModePrivate),
          let lambdaBuffer = device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride,
                                               options: .storageModePrivate) else {
      return nil
    }
    reduceTilesBuffer.label = "LiquidLight.reduceTiles"
    lambdaBuffer.label = "LiquidLight.lambda"
    self.reduceTilesBuffer = reduceTilesBuffer
    self.lambdaBuffer = lambdaBuffer

    self.device = device
    self.commandQueue = commandQueue
    self.commandBuffer = commandBuffer
    self.sharedEvent = sharedEvent
    self.commandAllocators = commandAllocators
    self.uniformBuffers = uniformBuffers
    self.currentUniformBuffer = firstUniformBuffer
    self.argumentTables = argumentTables
    self.seedPipeline = pipelines.seed
    self.advectPipeline = pipelines.advect
    self.reduceTilesPipeline = pipelines.reduceTiles
    self.reduceFinalPipeline = pipelines.reduceFinal
    self.relaxPipeline = pipelines.relax
    self.renderPipeline = pipelines.render
    self.feedbackPipeline = pipelines.feedback
    self.blurPipeline = pipelines.blur
    self.residencySet = residencySet

    configureResidencySet()
  }

  func prepareForResume() {
    lastFrameTime = 0
    resumeSuppressionRemaining = Self.resumeFadeDuration
    resumeFadeIn = 0
    historyValid = false

    envelope = .zero
    slowEnvelope = .zero
    smoothedBass = 0
    lastPressBass = 0
    smoothedSpeed = 0.25
  }

  private func ensureFrameTextures(width: Int, height: Int) -> FrameTextures? {
    if let existing = frameTextures, width == lastDrawableWidth, height == lastDrawableHeight {
      return existing
    }

    for old in frameTextures?.all ?? [] {
      pendingTextureReleases.append((frame: frameNumber, texture: old))
    }

    let simW = max(32, Int((Float(width) * Self.simScale / Self.renderScale).rounded()))
    let simH = max(32, Int((Float(height) * Self.simScale / Self.renderScale).rounded()))
    guard let textures = makeFrameTextures(width: width, height: height,
                                           simWidth: simW, simHeight: simH) else {
      frameTextures = nil
      lastDrawableWidth = 0
      lastDrawableHeight = 0
      return nil
    }

    for tex in textures.all { residencySet.addAllocation(tex) }
    residencySet.commit()

    frameTextures = textures
    historyValid = false
    simValid = false
    simWidth = simW
    simHeight = simH
    lastDrawableWidth = width
    lastDrawableHeight = height
    return textures
  }

  private func encodeSimulation(encoder: any MTL4ComputeCommandEncoder,
                                textures: FrameTextures,
                                audio: SIMD3<Float>) -> MTLTexture {
    var src = textures.phase[0]
    var dst = textures.phase[1]
    if !simValid {
      seedPhase(encoder: encoder, phaseOut: src)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
      simValid = true
    }

    advectPhase(encoder: encoder, phaseIn: src, phaseOut: dst, audio: audio)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    swap(&src, &dst)

    reduceMassMultiplier(encoder: encoder, phase: src)

    let relaxSteps = max(4, min(14, Int((dt * 60 * 7).rounded())))
    for _ in 0..<relaxSteps {
      relaxPhase(encoder: encoder, phaseIn: src, phaseOut: dst)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
      swap(&src, &dst)
    }

    if src !== textures.phase[0] {
      frameTextures = FrameTextures(intermediate: textures.intermediate,
                                    history: textures.history,
                                    final: textures.final,
                                    phase: [src, dst])
    }
    return src
  }

  func encodeFrame(bass: Float,
                   mid: Float,
                   high: Float,
                   drawableWidth: Int,
                   drawableHeight: Int) -> MTLTexture? {
    drainPendingReleases(&pendingTextureReleases)

    let smoothed = processAudio(bass: bass, mid: mid, high: high)

    let width = max(1, Int((Float(drawableWidth) * Self.renderScale).rounded()))
    let height = max(1, Int((Float(drawableHeight) * Self.renderScale).rounded()))
    guard let textures = ensureFrameTextures(width: width, height: height) else {
      return nil
    }

    guard let encoder = beginFrame() else { return nil }
    let parity = Int(frameNumber & 1)
    let finalTex = textures.final[parity]
    let historyIn = textures.history[1 - parity]
    let historyOut = textures.history[parity]

    let phase = encodeSimulation(encoder: encoder, textures: textures, audio: smoothed)

    renderLiquidLight(encoder: encoder, output: textures.intermediate, phase: phase, audio: smoothed)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    renderFeedback(encoder: encoder, render: textures.intermediate,
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
