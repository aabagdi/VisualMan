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

struct LiquidLightParams {
  var time: Float
  var bass: Float
  var mid: Float
  var high: Float
  var drops: LiquidLightDrops
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
  private var smoothedSpeed: Float = 0.05

  private var envelope: SIMD3<Float> = .zero

  private var smoothedBass: Float = 0
  private var lastDropTime: Float = -10
  private var drops: [SIMD4<Float>] = Array(repeating: SIMD4<Float>(0, 0, -1, 0), count: 4)
  private var nextDropSlot: Int = 0
  private var dropHueCounter: Float = 0

  static let maxFramesInFlight: UInt64 = 3
  private var commandAllocators = [any MTL4CommandAllocator]()
  private var commandBuffer: any MTL4CommandBuffer
  var argumentTable: any MTL4ArgumentTable
  var uniformBuffers = [MTLBuffer]()
  var uniformOffset: Int = 0
  static let uniformBufferSize: Int = 4096
  private let sharedEvent: MTLSharedEvent
  private var frameNumber: UInt64 = 0
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
        sharedEvent.wait(untilSignaledValue: frameNumber, timeoutMS: 1000)
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

  private func processAudio(bass: Float, mid: Float, high: Float) -> SIMD3<Float> {
    let input = SIMD3<Float>(bass, mid, high)
    let attack = SIMD3<Float>(repeating: 0.55)
    let decay  = SIMD3<Float>(repeating: 0.08)
    var rate = decay
    rate.replace(with: attack, where: input .> envelope)
    envelope += (input - envelope) * rate

    let audioEnergy = envelope.sum() / 3.0
    let targetSpeed = 0.05 + audioEnergy * 0.95
    let alpha: Float = targetSpeed > smoothedSpeed ? 0.08 : 0.06
    smoothedSpeed += (targetSpeed - smoothedSpeed) * alpha
    time += dt * smoothedSpeed

    let bassBaseline: Float = 0.08
    smoothedBass += (bass - smoothedBass) * (bass > smoothedBass ? 0.15 : 0.05)
    let transient = bass > smoothedBass * 1.6 && bass > bassBaseline
    let cooldownOK = (time - lastDropTime) > 0.35
    if transient && cooldownOK {
      lastDropTime = time
      dropHueCounter = (dropHueCounter + 0.37).truncatingRemainder(dividingBy: 1.0)
      let seed = Float(frameNumber) * 0.6180339
      let x = sin(seed * 12.9) * 0.4
      let y = cos(seed * 7.3) * 0.35
      drops[nextDropSlot] = SIMD4<Float>(x, y, time, dropHueCounter)
      nextDropSlot = (nextDropSlot + 1) % 4
    }

    return envelope
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

  private func renderLiquidLight(encoder: any MTL4ComputeCommandEncoder,
                                 output: MTLTexture,
                                 audio: SIMD3<Float>) {
    encoder.setComputePipelineState(renderPipeline)
    argumentTable.setTexture(output.gpuResourceID, index: 0)

    let params = LiquidLightParams(
      time: time, bass: audio.x, mid: audio.y, high: audio.z,
      drops: LiquidLightDrops(d0: drops[0], d1: drops[1], d2: drops[2], d3: drops[3])
    )
    argumentTable.setAddress(writeUniform(params), index: 0)

    let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
    let gridDimensions = MTLSize(width: output.width, height: output.height, depth: 1)
    encoder.dispatchThreads(threadsPerGrid: gridDimensions,
                            threadsPerThreadgroup: threadGroupSize)
  }

  private func renderBlur(encoder: any MTL4ComputeCommandEncoder,
                          input: MTLTexture,
                          output: MTLTexture,
                          audio: SIMD3<Float>) {
    encoder.setComputePipelineState(blurPipeline)

    argumentTable.setTexture(input.gpuResourceID, index: 0)
    argumentTable.setTexture(output.gpuResourceID, index: 1)

    let blurParams = BlurParams(
      innerRadius: 0.45 + audio.y * 0.05,
      outerRadius: 1.15,
      maxBlurRadius: 8.0 + audio.y * 2.0,
      texWidth: Float(input.width),
      texHeight: Float(input.height),
      bass: audio.x,
      mid: audio.y
    )
    argumentTable.setAddress(writeUniform(blurParams), index: 0)

    let tg = MTLSize(width: 16, height: 16, depth: 1)
    let groups = MTLSize(
      width: (output.width + 15) / 16,
      height: (output.height + 15) / 16,
      depth: 1
    )
    encoder.dispatchThreadgroups(threadgroupsPerGrid: groups, threadsPerThreadgroup: tg)
  }
}
