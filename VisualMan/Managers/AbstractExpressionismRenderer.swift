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
  var diffusePipeline: MTLComputePipelineState
  var lightPipeline: MTLComputePipelineState

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
  var hueOffset: Float = 0
  var strokeSeed: UInt32 = 0
  var isFirstFrame: Bool = true

  var songSeed: Float = Float.random(in: 0..<1000)
  var warmBias: Float = Float.random(in: 0.2..<0.8)

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

  private var canvasA: MTLTexture?
  private var canvasB: MTLTexture?
  private var heightA: MTLTexture?
  private var heightB: MTLTexture?
  private var displayTex: MTLTexture?
  private var lastDrawableWidth: Int = 0
  private var lastDrawableHeight: Int = 0

  var resumeSuppressionRemaining: Float = 0
  var resumeFadeIn: Float = 1.0
  static let resumeFadeDuration: Float = 0.8

  private var pendingTextureReleases: [(frame: UInt64, texture: MTLTexture)] = []

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
    setDesc.initialCapacity = 6
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
    self.diffusePipeline = pipelines.diffuse
    self.lightPipeline   = pipelines.light
    self.residencySet = residencySet

    configureResidencySet()
  }

  func warmUpGPU() {
    let colDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
    colDesc.usage = [.shaderRead, .shaderWrite]
    colDesc.storageMode = .private

    let hDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r16Float, width: 64, height: 64, mipmapped: false)
    hDesc.usage = [.shaderRead, .shaderWrite]
    hDesc.storageMode = .private

    guard let dA = device.makeTexture(descriptor: colDesc),
          let dB = device.makeTexture(descriptor: colDesc),
          let hA = device.makeTexture(descriptor: hDesc),
          let hB = device.makeTexture(descriptor: hDesc) else { return }

    [dA, dB, hA, hB].forEach { residencySet.addAllocation($0) }
    residencySet.commit()

    let warmupFrame: UInt64 = 1
    let idx = Int(warmupFrame % Self.maxFramesInFlight)
    let allocator = commandAllocators[idx]
    currentUniformBuffer = uniformBuffers[idx]
    allocator.reset()
    uniformOffset = 0

    commandBuffer.beginCommandBuffer(allocator: allocator)
    commandBuffer.useResidencySet(residencySet)
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setArgumentTable(argumentTable)

    let cc = Self.canvasColor
    let params = AbExParams(
      audio: .zero,
      canvas: SIMD4(cc.x, cc.y, cc.z, 0),
      config: SIMD4(0, 1, 0, 10))
    renderPaint(encoder: encoder,
                colorIn: dA, colorOut: dB,
                heightIn: hA, heightOut: hB,
                params: params, strokes: [])
    encoder.endEncoding()
    commandBuffer.endCommandBuffer()
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: warmupFrame)
    frameNumber = warmupFrame

    sharedEvent.wait(untilSignaledValue: warmupFrame, timeoutMS: 1000)
    [dA, dB, hA, hB].forEach { residencySet.removeAllocation($0) }
    residencySet.commit()
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
  }

  private func drainPendingTextureReleases() {
    drainPendingReleases(&pendingTextureReleases)
  }

  private func ensureCanvasTextures(width: Int, height: Int) -> Bool {
    if width == lastDrawableWidth
        && height == lastDrawableHeight
        && canvasA != nil && canvasB != nil
        && heightA != nil && heightB != nil
        && displayTex != nil {
      return true
    }

    for old in [canvasA, canvasB, heightA, heightB, displayTex] {
      if let t = old {
        pendingTextureReleases.append((frame: frameNumber, texture: t))
      }
    }

    let colDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    colDesc.usage = [.shaderRead, .shaderWrite]
    colDesc.storageMode = .private

    let hDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r16Float, width: width, height: height, mipmapped: false)
    hDesc.usage = [.shaderRead, .shaderWrite]
    hDesc.storageMode = .private

    guard let cA = device.makeTexture(descriptor: colDesc),
          let cB = device.makeTexture(descriptor: colDesc),
          let hA = device.makeTexture(descriptor: hDesc),
          let hB = device.makeTexture(descriptor: hDesc),
          let disp = device.makeTexture(descriptor: colDesc) else {
      canvasA = nil; canvasB = nil; heightA = nil; heightB = nil; displayTex = nil
      lastDrawableWidth = 0; lastDrawableHeight = 0
      return false
    }

    [cA, cB, hA, hB, disp].forEach { residencySet.addAllocation($0) }
    residencySet.commit()

    canvasA = cA; canvasB = cB
    heightA = hA; heightB = hB
    displayTex = disp
    lastDrawableWidth = width
    lastDrawableHeight = height
    isFirstFrame = true
    return true
  }

  func encodeFrame(bass: Float,
                   mid: Float,
                   high: Float,
                   drawableWidth: Int,
                   drawableHeight: Int) -> MTLTexture? {
    drainPendingTextureReleases()

    let smoothed = processAudio(bass: bass, mid: mid, high: high)

    guard ensureCanvasTextures(width: drawableWidth, height: drawableHeight),
          let cA = canvasA, let cB = canvasB,
          let hA = heightA, let hB = heightB,
          let disp = displayTex else { return nil }

    guard let encoder = beginFrame() else { return nil }

    let strokes = generateStrokes(audio: smoothed)

    let energy = (smoothed.x + smoothed.y + smoothed.z) / 3.0
    let dryRate: Float = 0.0003 + energy * 0.0002
    let diffusionRate: Float = 0.010 + energy * 0.015
    let bumpStrength: Float = 10.0   // raised from 7.0 for more visible impasto

    let cc = Self.canvasColor
    let params = AbExParams(
      audio: SIMD4(time, smoothed.x, smoothed.y, smoothed.z),
      canvas: SIMD4(cc.x, cc.y, cc.z, dryRate),
      config: SIMD4(diffusionRate,
                    isFirstFrame ? 1.0 : 0.0,
                    Float(strokes.count),
                    bumpStrength))

    renderPaint(encoder: encoder,
                colorIn: cA, colorOut: cB,
                heightIn: hA, heightOut: hB,
                params: params, strokes: strokes)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    renderDiffuse(encoder: encoder,
                  colorIn: cB, colorOut: cA,
                  heightIn: hB, heightOut: hA,
                  params: params)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    renderLight(encoder: encoder,
                colorIn: cA, heightIn: hA,
                colorOut: disp,
                params: params)

    encoder.barrier(afterStages: .dispatch, beforeQueueStages: .fragment)
    encoder.endEncoding()

    isFirstFrame = false
    return disp
  }
}
