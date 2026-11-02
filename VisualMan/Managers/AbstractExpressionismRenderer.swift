//
//  AbstractExpressionismRenderer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/23/26.
//

#if !targetEnvironment(simulator)
import Metal
import MetalKit
import os
import QuartzCore

struct AbExParams {
  var audio: SIMD4<Float>
  var canvas: SIMD4<Float>
  var config: SIMD4<Float>
  var camera: SIMD4<Float>
  var atmosphere: SIMD4<Float>
}

struct AbExStroke {
  var posAngle: SIMD4<Float>
  var sizeOpacity: SIMD4<Float>
  var color: SIMD4<Float>
  var animation: SIMD4<Float>
}

@MainActor
final class AbstractExpressionismRenderer: MetalVisualizerRenderer {
  let device: MTLDevice
  let commandQueue: any MTL4CommandQueue

  var paintPipeline: MTLComputePipelineState
  var composePipeline: MTLComputePipelineState
  var velocityPipeline: MTLComputePipelineState
  var resamplePipeline: MTLComputePipelineState

  var pendingResample: Bool = false
  var resampleColorSrc: MTLTexture?
  var resampleHeightWetSrc: MTLTexture?
  var resampleDryColorSrc: MTLTexture?
  var resampleSubstrateSrc: MTLTexture?

  var time: Float = 0
  var dt: Float = 1.0 / 60.0
  var lastFrameTime: CFTimeInterval = 0
  var wallClock: Float = 0

  var envelope: SIMD3<Float> = .zero
  var slowEnvelope: SIMD3<Float> = .zero

  var smoothedBass: Float = 0
  var lastGesturalTime: Float = -10
  var lastWashTime: Float = -10
  var lastSplatterTime: Float = -10
  var lastKnifeTime: Float = -10
  var lastPollockTime: Float = -10
  var lastScumbleTime: Float = -10
  var lastLineTime: Float = -10
  var lastDebugTrailTime: Float = -10

  var paintTestClock: Float = 0
  var paintTestEventIndex: Int = 0
  var paintTestStatus: String = "Paint test starting…"
  var paintTestDryMultiplier: Float = 1
  var framesSinceSmear: Int = 999
  var pollockEventCounter: Int = 0
  var hueOffset: Float = 0
  var strokeSeed: UInt32 = 0
  var isFirstFrame: Bool = true

  var songSeed: Float = Float.random(in: 0..<1000)
  var pigmentWeights: [Float] = []
  var pigmentWeightsSeed: Float = -1
  var warmBias: Float = Float.random(in: 0.2..<0.8)

  var cameraPhase: Float = 0

  var currentGestureRemaining: Int = 0
  var currentGestureAngle: Float = 0
  var currentGestureCenter: SIMD2<Float> = .zero
  var currentGestureStarted: Float = 0
  var currentGestureSpan: Float = 0.30
  static let gestureTimeoutSeconds: Float = 2.0

  static let flowGridSize: Int = 32
  static let flowDecayPerFrame: Float = 0.985
  static let flowDepositWeight: Float = 0.4
  static let flowMaxBlend: Float = 0.7

  var flowField: [SIMD2<Float>] = Array(
    repeating: .zero,
    count: AbstractExpressionismRenderer.flowGridSize
         * AbstractExpressionismRenderer.flowGridSize)

  static let densityGridSize: Int = 32
  static let densityDecayPerFrame: Float = 0.992
  static let densityDepositWeight: Float = 0.50
  static let densityMaxBias: Float = 0.65

  var densityGrid: [Float] = Array(
    repeating: 0,
    count: AbstractExpressionismRenderer.densityGridSize
         * AbstractExpressionismRenderer.densityGridSize)

  var paintedGrid: [Float] = Array(
    repeating: 0,
    count: AbstractExpressionismRenderer.densityGridSize
         * AbstractExpressionismRenderer.densityGridSize)

  static let canvasColor = AbstractExpressionismRenderer.srgbToLinear(
    SIMD3<Float>(0.95, 0.92, 0.87))
  static let canvasRenderScale: Float = 0.85
  static let maxStrokesPerFrame: Int = 9
  static let maxFramesInFlight: UInt64 = 3

  var commandAllocators = [any MTL4CommandAllocator]()
  var commandBuffer: any MTL4CommandBuffer
  var argumentTables: [any MTL4ArgumentTable]
  var uniformBuffers = [MTLBuffer]()
  var uniformOffset: Int = 0
  static let uniformBufferSize: Int = 65536
  let sharedEvent: MTLSharedEvent
  var frameNumber: UInt64 = 0
  let residencySet: MTLResidencySet
  nonisolated static let logger = Logger(subsystem: "com.VisualMan",
                                         category: "AbstractExpressionismRenderer")

  var currentUniformBuffer: MTLBuffer

  var colorA: MTLTexture?
  var colorB: MTLTexture?
  var heightWetA: MTLTexture?
  var heightWetB: MTLTexture?
  var colorMid: MTLTexture?
  var heightWetMid: MTLTexture?
  var velocityA: MTLTexture?
  var velocityB: MTLTexture?

  var dryColorA: MTLTexture?
  var dryColorB: MTLTexture?
  var dryColorMid: MTLTexture?

  var substrateA: MTLTexture?
  var substrateB: MTLTexture?

  var displayTextures: [MTLTexture] = []

  static let cullHiddenCanvas = true
  var fullCanvasFramesRemaining: Int = 0
  static let cameraMaxPan = SIMD2<Float>(0.015 + 0.006, 0.010 + 0.005)
  static let cameraMinZoom: Float = 1.0 - 0.020 - 0.008

  var mixboxLUT: MTLTexture?
  var crackTexture: MTLTexture?

  var canvasSize: Int = 0
  var lastDisplayWidth: Int = 0
  var lastDisplayHeight: Int = 0

  var currentIsA: Bool = true

  var resumeSuppressionRemaining: Float = 0
  var resumeFadeIn: Float = 1.0
  static let resumeFadeDuration: Float = 0.8

  var isPlaying: Bool = true

  var pendingClearFrames: Int = 0

  struct AnimatingStroke {
    var stroke: AbExStroke
    var currentFrame: Int
    var totalFrames: Int
  }
  var animatingStrokes: [AnimatingStroke] = []
  static let knifeAnimationFrames: Int = 14
  static let gesturalAnimationFrames: Int = 12
  static let scumbleAnimationFrames: Int = 20
  static let washAnimationFrames: Int = 40
  static let maxAnimatingStrokes: Int = 5

  var pendingTextureReleases: [(frame: UInt64, texture: MTLTexture)] = []

  static func create(device: MTLDevice) async -> AbstractExpressionismRenderer? {
    guard let pipelines = await compilePipelines(device: device) else { return nil }
    guard let renderer = AbstractExpressionismRenderer(device: device, pipelines: pipelines) else {
      return nil
    }
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
          let sharedEvent = device.makeSharedEvent() else { return nil }
    sharedEvent.signaledValue = 0

    guard let allocsAndBufs = Self.createAllocatorsAndBuffers(device: device) else { return nil }
    let commandAllocators = allocsAndBufs.allocators
    let uniformBuffers = allocsAndBufs.buffers
    guard let firstUniformBuffer = uniformBuffers.first else { return nil }
    guard let argumentTables = Self.createArgumentTables(device: device) else { return nil }

    let setDesc = MTLResidencySetDescriptor()
    setDesc.initialCapacity = 10
    guard let residencySet = try? device.makeResidencySet(descriptor: setDesc) else { return nil }

    self.device = device
    self.commandQueue = commandQueue
    self.commandBuffer = commandBuffer
    self.sharedEvent = sharedEvent
    self.commandAllocators = commandAllocators
    self.uniformBuffers = uniformBuffers
    self.currentUniformBuffer = firstUniformBuffer
    self.argumentTables = argumentTables
    self.paintPipeline   = pipelines.paint
    self.composePipeline = pipelines.compose
    self.velocityPipeline = pipelines.velocity
    self.resamplePipeline = pipelines.resample
    self.residencySet = residencySet

    guard let lut = Self.makeMixboxLUT(device: device) else { return nil }
    self.mixboxLUT = lut
    self.crackTexture = Self.makeCrackTexture(device: device)

    configureResidencySet()
  }

  func prepareForResume() {
    lastFrameTime = 0
    resumeSuppressionRemaining = Self.resumeFadeDuration
    resumeFadeIn = 0
    envelope = .zero
    slowEnvelope = .zero
    smoothedBass = 0
    songSeed = Float.random(in: 0..<1000)
    warmBias = Float.random(in: 0.2..<0.8)
    cameraPhase = 0
  }
}

#endif
