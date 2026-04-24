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

  private var colorBackA: MTLTexture?
  private var colorBackB: MTLTexture?
  private var colorMidA: MTLTexture?
  private var colorMidB: MTLTexture?
  private var colorFrontA: MTLTexture?
  private var colorFrontB: MTLTexture?
  private var heightBackA: MTLTexture?
  private var heightBackB: MTLTexture?
  private var heightMFA: MTLTexture?
  private var heightMFB: MTLTexture?
  private var displayTex: MTLTexture?
  private var canvasSize: Int = 0
  private var lastDisplayWidth: Int = 0
  private var lastDisplayHeight: Int = 0

  var currentIsA: Bool = true

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

  func warmUpGPU() {
    let colDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
    colDesc.usage = [.shaderRead, .shaderWrite]
    colDesc.storageMode = .private

    let hbDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r16Float, width: 64, height: 64, mipmapped: false)
    hbDesc.usage = [.shaderRead, .shaderWrite]
    hbDesc.storageMode = .private

    let hmfDesc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rg16Float, width: 64, height: 64, mipmapped: false)
    hmfDesc.usage = [.shaderRead, .shaderWrite]
    hmfDesc.storageMode = .private

    guard let bA = device.makeTexture(descriptor: colDesc),
          let bB = device.makeTexture(descriptor: colDesc),
          let mA = device.makeTexture(descriptor: colDesc),
          let mB = device.makeTexture(descriptor: colDesc),
          let fA = device.makeTexture(descriptor: colDesc),
          let fB = device.makeTexture(descriptor: colDesc),
          let hbA = device.makeTexture(descriptor: hbDesc),
          let hbB = device.makeTexture(descriptor: hbDesc),
          let hmfA = device.makeTexture(descriptor: hmfDesc),
          let hmfB = device.makeTexture(descriptor: hmfDesc),
          let disp = device.makeTexture(descriptor: colDesc) else { return }

    let dummies: [MTLTexture] = [bA, bB, mA, mB, fA, fB,
                                 hbA, hbB, hmfA, hmfB, disp]
    for t in dummies { residencySet.addAllocation(t) }
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
      config: SIMD4(0, 1, 0, 10),
      camera: SIMD4(0, 0, 1, 0))

    renderPaint(encoder: encoder,
                colorBackIn: bA, colorBackOut: bB,
                colorMidIn: mA, colorMidOut: mB,
                colorFrontIn: fA, colorFrontOut: fB,
                heightBackIn: hbA, heightBackOut: hbB,
                heightMFIn: hmfA, heightMFOut: hmfB,
                params: params, strokes: [])
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    renderCompose(encoder: encoder,
                  colorBack: bB, colorMid: mB, colorFront: fB,
                  heightBack: hbB, heightMF: hmfB,
                  output: disp, params: params)

    encoder.endEncoding()
    commandBuffer.endCommandBuffer()
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: warmupFrame)
    frameNumber = warmupFrame

    sharedEvent.wait(untilSignaledValue: warmupFrame, timeoutMS: 1000)
    for t in dummies { residencySet.removeAllocation(t) }
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
    cameraPhase = 0
  }

  private func drainPendingTextureReleases() {
    drainPendingReleases(&pendingTextureReleases)
  }

  private func ensureCanvasTextures(displayWidth: Int, displayHeight: Int) -> Bool {
    let requestedCanvasSize = max(displayWidth, displayHeight)
    let targetCanvasSize = max(canvasSize, requestedCanvasSize)

    let canvasExists = colorBackA != nil && colorBackB != nil
        && colorMidA != nil && colorMidB != nil
        && colorFrontA != nil && colorFrontB != nil
        && heightBackA != nil && heightBackB != nil
        && heightMFA != nil && heightMFB != nil
    let canvasNeedsRebuild = !canvasExists || targetCanvasSize > canvasSize

    if canvasNeedsRebuild {
      for old in [colorBackA, colorBackB, colorMidA, colorMidB,
                  colorFrontA, colorFrontB,
                  heightBackA, heightBackB,
                  heightMFA, heightMFB] {
        if let t = old {
          pendingTextureReleases.append((frame: frameNumber, texture: t))
        }
      }

      let colDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: targetCanvasSize, height: targetCanvasSize, mipmapped: false)
      colDesc.usage = [.shaderRead, .shaderWrite]
      colDesc.storageMode = .private

      let hbDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .r16Float, width: targetCanvasSize, height: targetCanvasSize, mipmapped: false)
      hbDesc.usage = [.shaderRead, .shaderWrite]
      hbDesc.storageMode = .private

      let hmfDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rg16Float, width: targetCanvasSize, height: targetCanvasSize, mipmapped: false)
      hmfDesc.usage = [.shaderRead, .shaderWrite]
      hmfDesc.storageMode = .private

      guard let bA = device.makeTexture(descriptor: colDesc),
            let bB = device.makeTexture(descriptor: colDesc),
            let mA = device.makeTexture(descriptor: colDesc),
            let mB = device.makeTexture(descriptor: colDesc),
            let fA = device.makeTexture(descriptor: colDesc),
            let fB = device.makeTexture(descriptor: colDesc),
            let hbA = device.makeTexture(descriptor: hbDesc),
            let hbB = device.makeTexture(descriptor: hbDesc),
            let hmfA = device.makeTexture(descriptor: hmfDesc),
            let hmfB = device.makeTexture(descriptor: hmfDesc) else {
        colorBackA = nil; colorBackB = nil
        colorMidA = nil;  colorMidB = nil
        colorFrontA = nil; colorFrontB = nil
        heightBackA = nil; heightBackB = nil
        heightMFA = nil;   heightMFB = nil
        canvasSize = 0
        return false
      }

      for t in [bA, bB, mA, mB, fA, fB,
                hbA, hbB, hmfA, hmfB] {
        residencySet.addAllocation(t)
      }

      colorBackA   = bA;  colorBackB   = bB
      colorMidA    = mA;  colorMidB    = mB
      colorFrontA  = fA;  colorFrontB  = fB
      heightBackA  = hbA; heightBackB  = hbB
      heightMFA    = hmfA; heightMFB   = hmfB
      canvasSize   = targetCanvasSize
      isFirstFrame = true
      currentIsA   = true
    }

    let displayNeedsRebuild = displayTex == nil
        || displayWidth != lastDisplayWidth
        || displayHeight != lastDisplayHeight

    if displayNeedsRebuild {
      if let old = displayTex {
        pendingTextureReleases.append((frame: frameNumber, texture: old))
      }
      let dispDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: displayWidth, height: displayHeight, mipmapped: false)
      dispDesc.usage = [.shaderRead, .shaderWrite]
      dispDesc.storageMode = .private
      guard let disp = device.makeTexture(descriptor: dispDesc) else {
        displayTex = nil
        lastDisplayWidth = 0; lastDisplayHeight = 0
        return false
      }
      residencySet.addAllocation(disp)
      displayTex = disp
      lastDisplayWidth = displayWidth
      lastDisplayHeight = displayHeight
    }

    if canvasNeedsRebuild || displayNeedsRebuild {
      residencySet.commit()
    }

    return true
  }

  func encodeFrame(bass: Float,
                   mid: Float,
                   high: Float,
                   drawableWidth: Int,
                   drawableHeight: Int) -> MTLTexture? {
    drainPendingTextureReleases()

    let smoothed = processAudio(bass: bass, mid: mid, high: high)

    guard ensureCanvasTextures(displayWidth: drawableWidth, displayHeight: drawableHeight) else { return nil }

    let readA = currentIsA
    guard let backIn    = readA ? colorBackA   : colorBackB,
          let backOut   = readA ? colorBackB   : colorBackA,
          let midIn     = readA ? colorMidA    : colorMidB,
          let midOut    = readA ? colorMidB    : colorMidA,
          let frontIn   = readA ? colorFrontA  : colorFrontB,
          let frontOut  = readA ? colorFrontB  : colorFrontA,
          let hbIn      = readA ? heightBackA  : heightBackB,
          let hbOut     = readA ? heightBackB  : heightBackA,
          let hmfIn     = readA ? heightMFA    : heightMFB,
          let hmfOut    = readA ? heightMFB    : heightMFA,
          let disp      = displayTex else { return nil }

    guard let encoder = beginFrame() else { return nil }

    let strokes = generateStrokes(audio: smoothed)

    let energy = (smoothed.x + smoothed.y + smoothed.z) / 3.0
    let dryRate: Float = 0.0003 + energy * 0.0002
    let bumpStrength: Float = 13.0

    cameraPhase += dt * 0.30
    let camPanX: Float = sin(cameraPhase * 0.13) * 0.015
                       + sin(cameraPhase * 0.29) * 0.006
    let camPanY: Float = cos(cameraPhase * 0.17) * 0.010
                       + sin(cameraPhase * 0.37) * 0.005
    let camZoom: Float = 1.0 + sin(cameraPhase * 0.20) * 0.020
                             + cos(cameraPhase * 0.43) * 0.008

    let cc = Self.canvasColor
    let params = AbExParams(
      audio: SIMD4(time, smoothed.x, smoothed.y, smoothed.z),
      canvas: SIMD4(cc.x, cc.y, cc.z, dryRate),
      config: SIMD4(0, isFirstFrame ? 1.0 : 0.0, Float(strokes.count), bumpStrength),
      camera: SIMD4(camPanX, camPanY, camZoom, 0))

    renderPaint(encoder: encoder,
                colorBackIn: backIn, colorBackOut: backOut,
                colorMidIn: midIn, colorMidOut: midOut,
                colorFrontIn: frontIn, colorFrontOut: frontOut,
                heightBackIn: hbIn, heightBackOut: hbOut,
                heightMFIn: hmfIn, heightMFOut: hmfOut,
                params: params, strokes: strokes)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    renderCompose(encoder: encoder,
                  colorBack: backOut, colorMid: midOut, colorFront: frontOut,
                  heightBack: hbOut, heightMF: hmfOut,
                  output: disp, params: params)

    encoder.barrier(afterStages: .dispatch, beforeQueueStages: .fragment)
    encoder.endEncoding()

    isFirstFrame = false
    currentIsA.toggle()
    return disp
  }
}
