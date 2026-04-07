//
//  NavierStokesRenderer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import Metal
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
final class NavierStokesRenderer {
  let device: MTLDevice
  let commandQueue: any MTL4CommandQueue
  
  static let gridSize: Int = 1024
  var gridSize: Int { Self.gridSize }
  
  var diffusePipeline: MTLComputePipelineState
  var advectPipeline: MTLComputePipelineState
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
  let dt: Float = 1.0 / 60.0
  var prevBass: Float = 0
  var prevMid: Float = 0
  private let velocityDissipation: Float = 0.99
  private let dyeDissipation: Float = 0.98
  let jacobiIterations: Int = 6
  let viscosity: Float = 0.0002
  let diffuseIterations: Int = 4
  let vorticityStrength: Float = 3.0
  
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
    
    let setDesc = MTLResidencySetDescriptor()
    setDesc.initialCapacity = 16
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
    self.splatBatchPipeline = pipelines.splatBatch
    self.diffusePipeline = pipelines.diffuse
    self.advectPipeline = pipelines.advect
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
  struct Pipelines {
    let splatBatch: MTLComputePipelineState
    let diffuse: MTLComputePipelineState
    let advect: MTLComputePipelineState
    let vorticityConfine: MTLComputePipelineState
    let divergence: MTLComputePipelineState
    let jacobi: MTLComputePipelineState
    let gradientSubtract: MTLComputePipelineState
    let blurH: MTLComputePipelineState
    let blurV: MTLComputePipelineState
    let bloomThreshold: MTLComputePipelineState
    let render: MTLComputePipelineState
  }
  
  static func createPipelines(device: MTLDevice, compiler: any MTL4Compiler) -> Pipelines? {
    guard let library = device.makeDefaultLibrary() else { return nil }
    
    func makePipeline(_ name: String) -> MTLComputePipelineState? {
      let functionDesc = MTL4LibraryFunctionDescriptor()
      functionDesc.name = name
      functionDesc.library = library
      let pipelineDesc = MTL4ComputePipelineDescriptor()
      pipelineDesc.computeFunctionDescriptor = functionDesc
      return try? compiler.makeComputePipelineState(descriptor: pipelineDesc)
    }
    
    guard let splatBatch = makePipeline("fluidSplatBatch"),
          let diffuse = makePipeline("fluidDiffuse"),
          let advect = makePipeline("fluidAdvect"),
          let vorticityConfine = makePipeline("fluidVorticityConfine"),
          let divergence = makePipeline("fluidDivergence"),
          let jacobi = makePipeline("fluidJacobi"),
          let gradientSubtract = makePipeline("fluidGradientSubtract"),
          let blurH = makePipeline("fluidBlurH"),
          let blurV = makePipeline("fluidBlurV"),
          let bloomThreshold = makePipeline("fluidBloomThreshold"),
          let render = makePipeline("fluidRender") else {
      return nil
    }
    
    return Pipelines(splatBatch: splatBatch, diffuse: diffuse, advect: advect,
                     vorticityConfine: vorticityConfine,
                     divergence: divergence, jacobi: jacobi,
                     gradientSubtract: gradientSubtract, blurH: blurH,
                     blurV: blurV, bloomThreshold: bloomThreshold,
                     render: render)
  }
  
  struct Textures {
    let velocityA: MTLTexture
    let velocityB: MTLTexture
    let pressure: MTLTexture
    let pressureTemp: MTLTexture
    let divergence: MTLTexture
    let dyeA: MTLTexture
    let dyeB: MTLTexture
    let bloomA: MTLTexture
    let bloomB: MTLTexture
  }
  
  static func createTextures(device: MTLDevice) -> Textures? {
    func makeTexture(format: MTLPixelFormat,
                     usage: MTLTextureUsage = [.shaderRead, .shaderWrite]) -> MTLTexture? {
      let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: format, width: gridSize, height: gridSize, mipmapped: false
      )
      desc.usage = usage
      desc.storageMode = .private
      return device.makeTexture(descriptor: desc)
    }
    
    guard let velocityA = makeTexture(format: .rg16Float),
          let velocityB = makeTexture(format: .rg16Float),
          let pressure = makeTexture(format: .r16Float),
          let pressureTemp = makeTexture(format: .r16Float),
          let divergence = makeTexture(format: .r16Float),
          let dyeA = makeTexture(format: .rgba16Float),
          let dyeB = makeTexture(format: .rgba16Float),
          let bloomA = makeTexture(format: .rgba16Float),
          let bloomB = makeTexture(format: .rgba16Float) else {
      return nil
    }
    
    return Textures(velocityA: velocityA, velocityB: velocityB,
                    pressure: pressure, pressureTemp: pressureTemp,
                    divergence: divergence, dyeA: dyeA, dyeB: dyeB,
                    bloomA: bloomA, bloomB: bloomB)
  }
  
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
    return try? device.makeArgumentTable(descriptor: desc)
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
