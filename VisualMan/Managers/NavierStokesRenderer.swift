//
//  NavierStokesRenderer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import Metal
import os
import QuartzCore

struct SplatParams {
  var position: SIMD2<Float>
  var radius: Float
  var padding: Float = 0
  var value: SIMD3<Float>
  var padding2: Float = 0

  init(position: SIMD2<Float>, value: SIMD3<Float>, radius: Float) {
    self.position = position
    self.value = value
    self.radius = radius
  }
}

@MainActor
final class NavierStokesRenderer: MetalVisualizerRenderer {
  let device: MTLDevice
  let commandQueue: any MTL4CommandQueue
  
  nonisolated static let logger = Logger(subsystem: "com.VisualMan", category: "NavierStokesRenderer")
  static let gridSize: Int = 1024
  var gridSize: Int { Self.gridSize }
  
  var advectPipeline: MTLComputePipelineState
  var divergencePipeline: MTLComputePipelineState
  var jacobiPipeline: MTLComputePipelineState
  var gradientSubtractPipeline: MTLComputePipelineState
  var splatBatchPipeline: MTLComputePipelineState
  var blurHPipeline: MTLComputePipelineState
  var blurVPipeline: MTLComputePipelineState
  var bloomThresholdPipeline: MTLComputePipelineState
  var renderPipeline: MTLComputePipelineState
  var psiInitPipeline: MTLComputePipelineState
  var psiAdvectPipeline: MTLComputePipelineState
  var covectorPullbackPipeline: MTLComputePipelineState
  var copyRGPipeline: MTLComputePipelineState
  var clearRGPipeline: MTLComputePipelineState
  var clearRGBAPipeline: MTLComputePipelineState
  
  var velocityA: MTLTexture
  var velocityB: MTLTexture
  var pressure: MTLTexture
  var pressureTemp: MTLTexture
  var divergenceTexture: MTLTexture
  var dyeA: MTLTexture
  var dyeB: MTLTexture
  var bloomA: MTLTexture
  var bloomB: MTLTexture
  var psiA: MTLTexture
  var psiB: MTLTexture
  var u0: MTLTexture
  
  var time: Float = 0
  var dt: Float = 1.0 / 60.0
  var prevBass: Float = 0
  var prevMid: Float = 0
  private let velocityDissipation: Float = 0.985
  private let dyeDissipation: Float = 0.98
  private let maxJacobiIterations: Int = 32
  private let rampUpFrames: UInt64 = 180
  var renderFrameCount: UInt64 = 0
  
  private static let maxFramesInFlight: UInt64 = 3
  private var commandAllocators = [any MTL4CommandAllocator]()
  private var commandBuffer: any MTL4CommandBuffer
  var argumentTable: any MTL4ArgumentTable
  private var uniformBuffers = [MTLBuffer]()
  private var uniformOffset: Int = 0
  private static let uniformBufferSize: Int = 16384
  private let sharedEvent: MTLSharedEvent
  private var frameNumber: UInt64 = 0
  private let residencySet: MTLResidencySet
  let reinitInterval: Int = 6
  var framesSinceReinit: Int = 6
  
  private var currentUniformBuffer: MTLBuffer
  
  static func create() async -> NavierStokesRenderer? {
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
    guard let renderer = NavierStokesRenderer(device: device, pipelines: pipelines) else { return nil }
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

    guard let allocatorsAndBuffers = Self.createAllocatorsAndBuffers(device: device),
          let firstUniformBuffer = allocatorsAndBuffers.buffers.first else { return nil }

    guard let argumentTable = Self.createArgumentTable(device: device) else { return nil }
    guard let textures = Self.createTextures(device: device) else { return nil }
    guard let residencySet = Self.createResidencySet(device: device) else { return nil }

    self.device = device
    self.commandQueue = commandQueue
    self.commandBuffer = commandBuffer
    self.sharedEvent = sharedEvent
    self.commandAllocators = allocatorsAndBuffers.allocators
    self.uniformBuffers = allocatorsAndBuffers.buffers
    self.currentUniformBuffer = firstUniformBuffer
    self.argumentTable = argumentTable
    
    self.splatBatchPipeline = pipelines.splatBatch
    self.advectPipeline = pipelines.advect
    self.psiInitPipeline = pipelines.psiInit
    self.psiAdvectPipeline = pipelines.psiAdvect
    self.covectorPullbackPipeline = pipelines.covectorPullback
    self.copyRGPipeline = pipelines.copyRG
    self.divergencePipeline = pipelines.divergence
    self.jacobiPipeline = pipelines.jacobi
    self.gradientSubtractPipeline = pipelines.gradientSubtract
    self.blurHPipeline = pipelines.blurH
    self.blurVPipeline = pipelines.blurV
    self.bloomThresholdPipeline = pipelines.bloomThreshold
    self.renderPipeline = pipelines.render
    self.clearRGPipeline = pipelines.clearRG
    self.clearRGBAPipeline = pipelines.clearRGBA
    
    self.velocityA = textures.velocityA
    self.velocityB = textures.velocityB
    self.pressure = textures.pressure
    self.pressureTemp = textures.pressureTemp
    self.divergenceTexture = textures.divergence
    self.dyeA = textures.dyeA
    self.dyeB = textures.dyeB
    self.bloomA = textures.bloomA
    self.bloomB = textures.bloomB
    self.psiA = textures.psiA
    self.psiB = textures.psiB
    self.u0 = textures.u0
    
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

  func writeUniformArray<T>(_ values: [T]) -> MTLGPUAddress {
    let aligned = (uniformOffset + 15) & ~15
    let size = MemoryLayout<T>.stride * values.count
    let end = aligned + size
    guard end <= Self.uniformBufferSize else {
      Self.logger.error("Uniform array buffer overflow: need \(end) bytes, have \(Self.uniformBufferSize)")
      return currentUniformBuffer.gpuAddress
    }
    let ptr = currentUniformBuffer.contents() + aligned
    values.withUnsafeBufferPointer { buf in
      if let baseAddress = buf.baseAddress {
        memcpy(ptr, baseAddress, size)
      }
    }
    let addr = currentUniformBuffer.gpuAddress + MTLGPUAddress(aligned)
    uniformOffset = end
    return addr
  }
  
  func update(bass: Float,
              mid: Float,
              high: Float,
              drawable: CAMetalDrawable) {
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
    
    renderFrameCount += 1
    time += dt * (1.0 + bass * 0.5 + mid * 0.3)

    commandBuffer.beginCommandBuffer(allocator: allocator)
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setArgumentTable(argumentTable)

    runSimulationPass(encoder: encoder, bass: bass, mid: mid, high: high,
                      output: drawable.texture)
    
    encoder.endEncoding()
    commandBuffer.endCommandBuffer()
    
    commandQueue.waitForDrawable(drawable)
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: frameNumber)
    commandQueue.signalDrawable(drawable)
    drawable.present()
  }

  private var currentJacobiIterations: Int {
    let t = min(Float(renderFrameCount) / Float(rampUpFrames), 1.0)
    return max(Int(Float(maxJacobiIterations) * t), 4)
  }
  
  private func runSimulationPass(encoder: any MTL4ComputeCommandEncoder,
                                 bass: Float, mid: Float, high: Float,
                                 output: MTLTexture) {
    advectPsi(encoder: encoder)
    swap(&psiA, &psiB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    covectorPullback(encoder: encoder, dissipation: 0.995)
    swap(&velocityA, &velocityB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    injectAudioSplats(encoder: encoder, bass: bass, mid: mid, high: high)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    project(encoder: encoder, jacobiIterations: currentJacobiIterations)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    framesSinceReinit += 1
    if framesSinceReinit >= reinitInterval {
      reinitFlowMap(encoder: encoder)
      framesSinceReinit = 0
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }

    let dynamicDyeDissipation: Float = 0.98 + bass * 0.01 + mid * 0.008
    advect(encoder: encoder, velocityIn: velocityA, fieldIn: dyeA,
           fieldOut: dyeB, dissipation: dynamicDyeDissipation)
    swap(&dyeA, &dyeB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    bloomThreshold(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    blurBloomH(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    blurBloomV(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    render(encoder: encoder, output: output, bass: bass, mid: mid)
  }
}

private extension NavierStokesRenderer {
  static func createAllocatorsAndBuffers(device: MTLDevice)
    -> (allocators: [any MTL4CommandAllocator], buffers: [MTLBuffer])? {
    var allocators = [any MTL4CommandAllocator]()
    var buffers = [MTLBuffer]()
    for _ in 0..<maxFramesInFlight {
      guard let allocator = device.makeCommandAllocator(),
            let buffer = device.makeBuffer(length: uniformBufferSize, options: .storageModeShared) else {
        return nil
      }
      allocators.append(allocator)
      buffers.append(buffer)
    }
    return (allocators, buffers)
  }
  
  static func createArgumentTable(device: MTLDevice) -> (any MTL4ArgumentTable)? {
    let desc = MTL4ArgumentTableDescriptor()
    desc.maxTextureBindCount = 3
    desc.maxBufferBindCount = 3
    do {
      return try device.makeArgumentTable(descriptor: desc)
    } catch {
      logger.error("Failed to create argument table: \(error.localizedDescription)")
      return nil
    }
  }
  
  func warmUpGPU() {
    let allocator = commandAllocators[0]
    currentUniformBuffer = uniformBuffers[0]
    allocator.reset()
    uniformOffset = 0

    commandBuffer.beginCommandBuffer(allocator: allocator)
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setArgumentTable(argumentTable)

    encoder.setComputePipelineState(clearRGPipeline)
    for tex in [velocityA, velocityB, u0] {
      argumentTable.setTexture(tex.gpuResourceID, index: 0)
      dispatchGrid(encoder: encoder)
    }

    for tex in [pressure, pressureTemp, divergenceTexture] {
      argumentTable.setTexture(tex.gpuResourceID, index: 0)
      dispatchGrid(encoder: encoder)
    }

    encoder.setComputePipelineState(clearRGBAPipeline)
    for tex in [dyeA, dyeB, bloomA, bloomB] {
      argumentTable.setTexture(tex.gpuResourceID, index: 0)
      dispatchGrid(encoder: encoder)
    }

    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(psiInitPipeline)
    argumentTable.setTexture(psiA.gpuResourceID, index: 0)
    dispatchGrid(encoder: encoder)

    encoder.endEncoding()
    commandBuffer.endCommandBuffer()
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: 1)
    frameNumber = 1
  }

  func configureResidencySet() {
    residencySet.addAllocation(velocityA)
    residencySet.addAllocation(velocityB)
    residencySet.addAllocation(pressure)
    residencySet.addAllocation(pressureTemp)
    residencySet.addAllocation(divergenceTexture)
    residencySet.addAllocation(dyeA)
    residencySet.addAllocation(dyeB)
    residencySet.addAllocation(bloomA)
    residencySet.addAllocation(bloomB)
    residencySet.addAllocation(psiA)
    residencySet.addAllocation(psiB)
    residencySet.addAllocation(u0)
    
    for buf in uniformBuffers { residencySet.addAllocation(buf) }
    
    residencySet.commit()
    
    commandQueue.addResidencySet(residencySet)
  }
}
