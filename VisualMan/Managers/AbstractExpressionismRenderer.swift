//
//  AbstractExpressionismRenderer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/23/26.
//

import Metal
import os
import QuartzCore

struct AbExParams {
  var audio: SIMD4<Float>
  var canvas: SIMD4<Float>
  var config: SIMD4<Float>
  var camera: SIMD4<Float>
}

struct AbExStroke {
  var posAngle: SIMD4<Float>
  var sizeOpacity: SIMD4<Float>
  var color: SIMD4<Float>
}

@MainActor
final class AbstractExpressionismRenderer: MetalVisualizerRenderer {
  let device: MTLDevice
  let commandQueue: any MTL4CommandQueue

  var paintPipeline: MTLComputePipelineState
  var composePipeline: MTLComputePipelineState

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
  var lastDebugTrailTime: Float = -10
  var pollockEventCounter: Int = 0
  var hueOffset: Float = 0
  var strokeSeed: UInt32 = 0
  var isFirstFrame: Bool = true

  var songSeed: Float = Float.random(in: 0..<1000)
  var warmBias: Float = Float.random(in: 0.2..<0.8)

  var cameraPhase: Float = 0

  static let canvasColor = SIMD3<Float>(0.95, 0.92, 0.87)
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
  nonisolated static let logger = Logger(subsystem: "com.VisualMan",
                                         category: "AbstractExpressionismRenderer")

  var currentUniformBuffer: MTLBuffer

  var colorA: MTLTexture?
  var colorB: MTLTexture?
  var heightWetA: MTLTexture?
  var heightWetB: MTLTexture?

  var displayTex: MTLTexture?

  var canvasSize: Int = 0
  var lastDisplayWidth: Int = 0
  var lastDisplayHeight: Int = 0

  var currentIsA: Bool = true

  var resumeSuppressionRemaining: Float = 0
  var resumeFadeIn: Float = 1.0
  static let resumeFadeDuration: Float = 0.8

  var pendingTextureReleases: [(frame: UInt64, texture: MTLTexture)] = []

  static func create(device: MTLDevice) async -> AbstractExpressionismRenderer? {
    let pipelines = await Task.detached(priority: .userInitiated) {
      guard let compiler = try? device.makeCompiler(descriptor: MTL4CompilerDescriptor()) else {
        return nil as Pipelines?
      }
      return createPipelines(device: device, compiler: compiler)
    }.value

    guard let pipelines else { return nil }
    guard let renderer = AbstractExpressionismRenderer(device: device, pipelines: pipelines) else {
      return nil
    }
    renderer.warmUpGPU()
    return renderer
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
    self.residencySet = residencySet

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
