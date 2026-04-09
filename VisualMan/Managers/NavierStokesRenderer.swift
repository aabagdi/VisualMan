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
  
  static let logger = Logger(subsystem: "com.VisualMan", category: "NavierStokesRenderer")
  static let gridSize: Int = 1024
  var gridSize: Int { Self.gridSize }
  
  var diffusePipeline: MTLComputePipelineState
  var advectPipeline: MTLComputePipelineState
  var covectorAdvectPipeline: MTLComputePipelineState
  var vorticityConfinePipeline: MTLComputePipelineState
  var divergencePipeline: MTLComputePipelineState
  var jacobiPipeline: MTLComputePipelineState
  var gradientSubtractPipeline: MTLComputePipelineState
  var splatBatchPipeline: MTLComputePipelineState
  var blurHPipeline: MTLComputePipelineState
  var blurVPipeline: MTLComputePipelineState
  var bloomThresholdPipeline: MTLComputePipelineState
  var renderPipeline: MTLComputePipelineState
  
  var velocityA: MTLTexture
  private var velocityB: MTLTexture
  var pressure: MTLTexture
  var pressureTemp: MTLTexture
  var divergenceTexture: MTLTexture
  var dyeA: MTLTexture
  var dyeB: MTLTexture
  var bloomA: MTLTexture
  var bloomB: MTLTexture
  
  var time: Float = 0
  var dt: Float = 1.0 / 60.0
  var prevBass: Float = 0
  var prevMid: Float = 0
  private let velocityDissipation: Float = 0.985
  private let dyeDissipation: Float = 0.98
  // More Jacobi iterations — the pressure solve is now doing Helmholtz
  // decomposition of the covector field, so convergence matters more
  let jacobiIterations: Int = 8
  // Restored close to original — diffusion still needed for stability
  let viscosity: Float = 0.0002
  let diffuseIterations: Int = 4
  // Covector advection preserves vorticity naturally — only a light touch
  let vorticityStrength: Float = 0.5
  
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
  
  private var currentUniformBuffer: MTLBuffer
  
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
    
    guard let textures = Self.createTextures(device: device) else { return nil }
    
    let rsDesc = MTLResidencySetDescriptor()
    rsDesc.initialCapacity = 16
    guard let residencySet = try? device.makeResidencySet(descriptor: rsDesc) else { return nil }
    
    self.device = device
    self.commandQueue = commandQueue
    self.commandBuffer = commandBuffer
    self.sharedEvent = sharedEvent
    self.commandAllocators = commandAllocators
    self.uniformBuffers = uniformBuffers
    self.currentUniformBuffer = firstUniformBuffer
    self.argumentTable = argumentTable
    self.splatBatchPipeline = pipelines.splatBatch
    self.diffusePipeline = pipelines.diffuse
    self.advectPipeline = pipelines.advect
    self.covectorAdvectPipeline = pipelines.covectorAdvect
    self.vorticityConfinePipeline = pipelines.vorticityConfine
    self.divergencePipeline = pipelines.divergence
    self.jacobiPipeline = pipelines.jacobi
    self.gradientSubtractPipeline = pipelines.gradientSubtract
    self.blurHPipeline = pipelines.blurH
    self.blurVPipeline = pipelines.blurV
    self.bloomThresholdPipeline = pipelines.bloomThreshold
    self.renderPipeline = pipelines.render
    self.velocityA = textures.velocityA
    self.velocityB = textures.velocityB
    self.pressure = textures.pressure
    self.pressureTemp = textures.pressureTemp
    self.divergenceTexture = textures.divergence
    self.dyeA = textures.dyeA
    self.dyeB = textures.dyeB
    self.bloomA = textures.bloomA
    self.bloomB = textures.bloomB
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
    
    time += dt * (1.0 + bass * 0.5)
    
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

  private func runSimulationPass(encoder: any MTL4ComputeCommandEncoder,
                                 bass: Float, mid: Float, high: Float,
                                 output: MTLTexture) {
    injectAudioSplats(encoder: encoder, bass: bass, mid: mid, high: high)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    diffuseField(encoder: encoder, fieldA: &velocityA, fieldB: &velocityB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    applyVorticityConfinement(encoder: encoder, bass: bass)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    advectCovector(encoder: encoder,
                   velocityIn: velocityA,
                   covectorOut: velocityB,
                   dissipation: velocityDissipation)
    swap(&velocityA, &velocityB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    project(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    let dynamicDyeDissipation = dyeDissipation + bass * 0.015
    advect(encoder: encoder, velocityIn: velocityA, fieldIn: dyeA,
           fieldOut: dyeB, dissipation: dynamicDyeDissipation)
    swap(&dyeA, &dyeB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    blurDyeH(encoder: encoder)
    swap(&dyeA, &dyeB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    blurDyeV(encoder: encoder)
    swap(&dyeA, &dyeB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    bloomThreshold(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    blurBloomH(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    blurBloomV(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    render(encoder: encoder, output: output, bass: bass)
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
    
    for buf in uniformBuffers { residencySet.addAllocation(buf) }
    
    residencySet.commit()
    
    commandQueue.addResidencySet(residencySet)
  }
}
