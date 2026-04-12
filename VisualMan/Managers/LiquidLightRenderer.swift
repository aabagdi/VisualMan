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
  private var lastDrawableWidth: Int = 0
  private var lastDrawableHeight: Int = 0

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
    return LiquidLightRenderer(device: device, pipelines: pipelines)
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

  func writeUniform<T>(_ value: T) -> MTLGPUAddress {
    let aligned = (uniformOffset + 15) & ~15
    let end = aligned + MemoryLayout<T>.size
    guard end <= Self.uniformBufferSize else {
      Self.logger.error("Uniform buffer overflow: need \(end) bytes, have \(Self.uniformBufferSize)")
      return currentUniformBuffer.gpuAddress
    }
    (currentUniformBuffer.contents() + aligned).storeBytes(of: value, as: T.self)
    let addr = currentUniformBuffer.gpuAddress + MTLGPUAddress(aligned)
    uniformOffset = end
    return addr
  }

  private func ensureIntermediateTexture(width: Int, height: Int) {
    if width == lastDrawableWidth && height == lastDrawableHeight && intermediateTexture != nil {
      return
    }

    if let old = intermediateTexture {
      if frameNumber > 0 {
        let ok = sharedEvent.wait(untilSignaledValue: frameNumber, timeoutMS: 1000)
        if !ok {
          Self.logger.error("Timed out waiting for GPU before recreating intermediate texture; keeping old texture")
          return
        }
      }
      residencySet.removeAllocation(old)
    }

    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private

    guard let tex = device.makeTexture(descriptor: desc) else {
      intermediateTexture = nil
      lastDrawableWidth = 0
      lastDrawableHeight = 0
      residencySet.commit()
      return
    }

    residencySet.addAllocation(tex)
    residencySet.commit()

    intermediateTexture = tex
    lastDrawableWidth = width
    lastDrawableHeight = height
  }

  func update(bass: Float,
              mid: Float,
              high: Float,
              drawable: CAMetalDrawable) {
    let smoothed = processAudio(bass: bass, mid: mid, high: high)

    let nextFrame = frameNumber + 1
    let frameIndex = Int(nextFrame % Self.maxFramesInFlight)

    if nextFrame > Self.maxFramesInFlight {
      let waitValue = nextFrame - Self.maxFramesInFlight
      guard sharedEvent.signaledValue >= waitValue else { return }
    }

    frameNumber = nextFrame

    let allocator = commandAllocators[frameIndex]
    currentUniformBuffer = uniformBuffers[frameIndex]
    allocator.reset()
    uniformOffset = 0

    let outputTex = drawable.texture
    ensureIntermediateTexture(width: outputTex.width, height: outputTex.height)
    guard let intermediateTex = intermediateTexture else { return }

    commandBuffer.beginCommandBuffer(allocator: allocator)
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setArgumentTable(argumentTable)

    renderLiquidLight(encoder: encoder, output: intermediateTex, audio: smoothed)

    renderBlur(encoder: encoder, input: intermediateTex, output: outputTex, audio: smoothed)

    encoder.endEncoding()
    commandBuffer.endCommandBuffer()

    commandQueue.waitForDrawable(drawable)
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: frameNumber)
    commandQueue.signalDrawable(drawable)
    drawable.present()
  }
}
