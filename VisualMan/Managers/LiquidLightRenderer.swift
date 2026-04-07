//
//  LiquidLightRenderer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/7/26.
//

import Metal
import QuartzCore

struct LiquidLightParams {
  var time: Float
  var bass: Float
  var mid: Float
  var high: Float
}

struct BlurParams {
  var innerRadius: Float
  var outerRadius: Float
  var maxBlurRadius: Float
  var texWidth: Float
  var texHeight: Float
}

@MainActor
final class LiquidLightRenderer {
  let device: MTLDevice
  let commandQueue: any MTL4CommandQueue

  var renderPipeline: MTLComputePipelineState
  var blurPipeline: MTLComputePipelineState

  var time: Float = 0
  let dt: Float = 1.0 / 60.0

  static let maxFramesInFlight: UInt64 = 3
  private var commandAllocators = [any MTL4CommandAllocator]()
  private var commandBuffer: any MTL4CommandBuffer
  var argumentTable: any MTL4ArgumentTable
  var uniformBuffers = [MTLBuffer]()
  var uniformOffset: Int = 0
  static let uniformBufferSize: Int = 4096
  private let sharedEvent: MTLSharedEvent
  private var frameNumber: UInt64 = 0
  var residencySet: MTLResidencySet

  var currentUniformBuffer: MTLBuffer

  private var intermediateTexture: MTLTexture?
  private var lastDrawableWidth: Int = 0
  private var lastDrawableHeight: Int = 0

  init?() {
    guard let device = MTLCreateSystemDefaultDevice(),
          let commandQueue = device.makeMTL4CommandQueue(),
          let commandBuffer = device.makeCommandBuffer(),
          let sharedEvent = device.makeSharedEvent(),
          let compiler = try? device.makeCompiler(descriptor: MTL4CompilerDescriptor()) else {
      return nil
    }
    sharedEvent.signaledValue = 0

    guard let allocatorsAndBuffers = Self.createAllocatorsAndBuffers(device: device) else { return nil }
    let commandAllocators = allocatorsAndBuffers.allocators
    let uniformBuffers = allocatorsAndBuffers.buffers
    guard let firstUniformBuffer = uniformBuffers.first else { return nil }

    guard let argumentTable = Self.createArgumentTable(device: device) else { return nil }

    guard let pipelines = Self.createPipelines(device: device, compiler: compiler) else { return nil }

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
    precondition(end <= Self.uniformBufferSize,
                 "Uniform buffer overflow: need \(end) bytes, have \(Self.uniformBufferSize)")
    (currentUniformBuffer.contents() + aligned).storeBytes(of: value, as: T.self)
    let addr = currentUniformBuffer.gpuAddress + MTLGPUAddress(aligned)
    uniformOffset = end
    return addr
  }

  private func ensureIntermediateTexture(width: Int, height: Int) {
    if width == lastDrawableWidth && height == lastDrawableHeight && intermediateTexture != nil {
      return
    }

    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private

    guard let tex = device.makeTexture(descriptor: desc) else { return }

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
    frameNumber += 1
    let frameIndex = Int(frameNumber % Self.maxFramesInFlight)

    let waitValue = frameNumber > Self.maxFramesInFlight
      ? frameNumber - Self.maxFramesInFlight
      : 0
    sharedEvent.wait(untilSignaledValue: waitValue, timeoutMS: 1000)

    let allocator = commandAllocators[frameIndex]
    currentUniformBuffer = uniformBuffers[frameIndex]
    allocator.reset()
    uniformOffset = 0

    time += dt

    let outputTex = drawable.texture
    ensureIntermediateTexture(width: outputTex.width, height: outputTex.height)
    guard let intermediateTex = intermediateTexture else { return }

    commandBuffer.beginCommandBuffer(allocator: allocator)
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setArgumentTable(argumentTable)

    renderLiquidLight(encoder: encoder, output: intermediateTex,
                      bass: bass, mid: mid, high: high)

    renderBlur(encoder: encoder, input: intermediateTex, output: outputTex)

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
                                 bass: Float, mid: Float, high: Float) {
    encoder.setComputePipelineState(renderPipeline)
    argumentTable.setTexture(output.gpuResourceID, index: 0)

    let params = LiquidLightParams(time: time, bass: bass, mid: mid, high: high)
    argumentTable.setAddress(writeUniform(params), index: 0)

    let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
    let gridDimensions = MTLSize(width: output.width, height: output.height, depth: 1)
    encoder.dispatchThreads(threadsPerGrid: gridDimensions,
                            threadsPerThreadgroup: threadGroupSize)
  }

  private func renderBlur(encoder: any MTL4ComputeCommandEncoder,
                          input: MTLTexture,
                          output: MTLTexture) {
    encoder.setComputePipelineState(blurPipeline)

    argumentTable.setTexture(input.gpuResourceID, index: 0)
    argumentTable.setTexture(output.gpuResourceID, index: 1)

    let blurParams = BlurParams(
      innerRadius: 0.35,
      outerRadius: 0.75,
      maxBlurRadius: 20.0,
      texWidth: Float(input.width),
      texHeight: Float(input.height)
    )
    argumentTable.setAddress(writeUniform(blurParams), index: 0)

    let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
    let gridDimensions = MTLSize(width: output.width, height: output.height, depth: 1)
    encoder.dispatchThreads(threadsPerGrid: gridDimensions,
                            threadsPerThreadgroup: threadGroupSize)
  }
}
