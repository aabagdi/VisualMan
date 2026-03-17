//
//  NavierStokesRenderer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import Metal
import MetalKit
import simd

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
final class NavierStokesRenderer {
  let device: MTLDevice
  let commandQueue: any MTL4CommandQueue
  
  let gridSize: Int = 1536
  
  var splatPipeline: MTLComputePipelineState!
  var diffusePipeline: MTLComputePipelineState!
  var advectPipeline: MTLComputePipelineState!
  var vorticityPipeline: MTLComputePipelineState!
  var vorticityForcePipeline: MTLComputePipelineState!
  var divergencePipeline: MTLComputePipelineState!
  var jacobiPipeline: MTLComputePipelineState!
  var gradientSubtractPipeline: MTLComputePipelineState!
  var splatBatchPipeline: MTLComputePipelineState!
  var blurHPipeline: MTLComputePipelineState!
  var blurVPipeline: MTLComputePipelineState!
  var renderPipeline: MTLComputePipelineState!
  
  var velocityA: MTLTexture!
  private var velocityB: MTLTexture!
  var pressure: MTLTexture!
  var pressureTemp: MTLTexture!
  var divergenceTexture: MTLTexture!
  var dyeA: MTLTexture!
  var dyeB: MTLTexture!
  var vorticityTexture: MTLTexture!
  
  var time: Float = 0
  let dt: Float = 1.0 / 60.0
  var prevBass: Float = 0
  var prevMid: Float = 0
  private let velocityDissipation: Float = 0.99
  private let dyeDissipation: Float = 0.98
  let jacobiIterations: Int = 10
  let viscosity: Float = 0.0002
  let diffuseIterations: Int = 4
  let vorticityStrength: Float = 1.5
  
  private static let maxFramesInFlight: UInt64 = 3
  private var commandAllocators: [any MTL4CommandAllocator] = []
  private var commandBuffer: any MTL4CommandBuffer
  var argumentTable: any MTL4ArgumentTable
  private var uniformBuffers: [MTLBuffer] = []
  private var uniformOffset: Int = 0
  private static let uniformBufferSize: Int = 16384
  private var sharedEvent: MTLSharedEvent!
  private var frameNumber: UInt64 = 0
  private var residencySet: MTLResidencySet!
  
  private var currentUniformBuffer: MTLBuffer!
  
  init?() {
    guard let device = MTLCreateSystemDefaultDevice(),
          let commandQueue = device.makeMTL4CommandQueue(),
          let commandBuffer = device.makeCommandBuffer(),
          let sharedEvent = device.makeSharedEvent(),
          let compiler = try? device.makeCompiler(descriptor: MTL4CompilerDescriptor()) else {
      return nil
    }
    self.device = device
    self.commandQueue = commandQueue
    self.commandBuffer = commandBuffer
    self.sharedEvent = sharedEvent
    sharedEvent.signaledValue = 0
    
    for _ in 0..<Self.maxFramesInFlight {
      guard let allocator = device.makeCommandAllocator(),
            let uniformBuf = device.makeBuffer(length: Self.uniformBufferSize, options: .storageModeShared) else {
        return nil
      }
      commandAllocators.append(allocator)
      uniformBuffers.append(uniformBuf)
    }
    
    let tableDesc = MTL4ArgumentTableDescriptor()
    tableDesc.maxTextureBindCount = 3
    tableDesc.maxBufferBindCount = 3
    guard let argumentTable = try? device.makeArgumentTable(descriptor: tableDesc) else {
      return nil
    }
    self.argumentTable = argumentTable
    
    setupPipelines(compiler: compiler)
    setupTextures()
    
    let setDesc = MTLResidencySetDescriptor()
    setDesc.initialCapacity = 16
    guard let residencySet = try? device.makeResidencySet(descriptor: setDesc) else {
      return nil
    }
    self.residencySet = residencySet
    
    residencySet.addAllocation(velocityA!)
    residencySet.addAllocation(velocityB!)
    residencySet.addAllocation(pressure!)
    residencySet.addAllocation(pressureTemp!)
    residencySet.addAllocation(divergenceTexture!)
    residencySet.addAllocation(dyeA!)
    residencySet.addAllocation(dyeB!)
    residencySet.addAllocation(vorticityTexture!)
    
    for buf in uniformBuffers { residencySet.addAllocation(buf) }
    
    residencySet.commit()
    
    commandQueue.addResidencySet(residencySet)
  }
  
  private func setupPipelines(compiler: any MTL4Compiler) {
    guard let library = device.makeDefaultLibrary() else { return }
    
    func makePipeline(_ name: String) -> MTLComputePipelineState? {
      let functionDesc = MTL4LibraryFunctionDescriptor()
      functionDesc.name = name
      functionDesc.library = library
      
      let pipelineDesc = MTL4ComputePipelineDescriptor()
      pipelineDesc.computeFunctionDescriptor = functionDesc
      
      return try? compiler.makeComputePipelineState(descriptor: pipelineDesc)
    }
    
    splatPipeline = makePipeline("fluidSplat")
    splatBatchPipeline = makePipeline("fluidSplatBatch")
    diffusePipeline = makePipeline("fluidDiffuse")
    advectPipeline = makePipeline("fluidAdvect")
    vorticityPipeline = makePipeline("fluidVorticity")
    vorticityForcePipeline = makePipeline("fluidVorticityForce")
    divergencePipeline = makePipeline("fluidDivergence")
    jacobiPipeline = makePipeline("fluidJacobi")
    gradientSubtractPipeline = makePipeline("fluidGradientSubtract")
    blurHPipeline = makePipeline("fluidBlurH")
    blurVPipeline = makePipeline("fluidBlurV")
    renderPipeline = makePipeline("fluidRender")
  }
  
  private func setupTextures() {
    velocityA = makeTexture(format: .rg16Float, usage: [.shaderRead, .shaderWrite])
    velocityB = makeTexture(format: .rg16Float, usage: [.shaderRead, .shaderWrite])
    pressure = makeTexture(format: .r16Float, usage: [.shaderRead, .shaderWrite])
    pressureTemp = makeTexture(format: .r16Float, usage: [.shaderRead, .shaderWrite])
    divergenceTexture = makeTexture(format: .r16Float, usage: [.shaderRead, .shaderWrite])
    dyeA = makeTexture(format: .rgba16Float, usage: [.shaderRead, .shaderWrite])
    dyeB = makeTexture(format: .rgba16Float, usage: [.shaderRead, .shaderWrite])
    vorticityTexture = makeTexture(format: .r16Float, usage: [.shaderRead, .shaderWrite])
  }
  
  private func makeTexture(format: MTLPixelFormat,
                           usage: MTLTextureUsage = [.shaderRead, .shaderWrite]) -> MTLTexture? {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: format,
      width: gridSize,
      height: gridSize,
      mipmapped: false
    )
    desc.usage = usage
    desc.storageMode = .private
    return device.makeTexture(descriptor: desc)
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

  func writeUniformArray<T>(_ values: [T]) -> MTLGPUAddress {
    let aligned = (uniformOffset + 15) & ~15
    let size = MemoryLayout<T>.stride * values.count
    let end = aligned + size
    precondition(end <= Self.uniformBufferSize,
                 "Uniform buffer overflow: need \(end) bytes, have \(Self.uniformBufferSize)")
    let ptr = currentUniformBuffer.contents() + aligned
    _ = values.withUnsafeBufferPointer { buf in
      memcpy(ptr, buf.baseAddress!, size)
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
    
    project(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    computeVorticity(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    applyVorticityForce(encoder: encoder, bass: bass)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    advect(encoder: encoder, velocityIn: velocityA, fieldIn: velocityA,
           fieldOut: velocityB, dissipation: velocityDissipation)
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
    
    render(encoder: encoder, output: output, bass: bass)
  }
  
}
