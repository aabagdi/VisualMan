//
//  NavierStokesRenderer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import Metal
import MetalKit
import simd

@MainActor
final class NavierStokesRenderer {
  let device: MTLDevice
  let commandQueue: any MTL4CommandQueue
  
  private let gridSize: Int = 1536
  
  private var splatPipeline: MTLComputePipelineState!
  private var advectPipeline: MTLComputePipelineState!
  private var divergencePipeline: MTLComputePipelineState!
  private var jacobiPipeline: MTLComputePipelineState!
  private var gradientSubtractPipeline: MTLComputePipelineState!
  private var blurHPipeline: MTLComputePipelineState!
  private var blurVPipeline: MTLComputePipelineState!
  private var renderPipeline: MTLComputePipelineState!
  
  private var velocityA: MTLTexture!
  private var velocityB: MTLTexture!
  private var pressure: MTLTexture!
  private var pressureTemp: MTLTexture!
  private var divergenceTexture: MTLTexture!
  private var dyeA: MTLTexture!
  private var dyeB: MTLTexture!
  
  private(set) var outputTexture: MTLTexture?
  
  private var time: Float = 0
  private let dt: Float = 1.0 / 60.0
  private let velocityDissipation: Float = 0.995
  private let dyeDissipation: Float = 0.99
  private let jacobiIterations: Int = 20
  
  // Metal 4 infrastructure — triple-buffered
  private static let maxFramesInFlight: UInt64 = 3
  private var commandAllocators: [any MTL4CommandAllocator] = []
  private var commandBuffer: any MTL4CommandBuffer
  private var argumentTable: any MTL4ArgumentTable
  private var uniformBuffers: [MTLBuffer] = []
  private var uniformOffset: Int = 0
  private var sharedEvent: MTLSharedEvent!
  private var frameNumber: UInt64 = 0
  private var residencySet: MTLResidencySet!
  
  private var currentUniformBuffer: MTLBuffer!
  
  init?() {
    guard let device = MTLCreateSystemDefaultDevice(),
          let commandQueue = device.makeMTL4CommandQueue(),
          let commandBuffer = device.makeCommandBuffer(),
          let sharedEvent = device.makeSharedEvent() else {
      return nil
    }
    self.device = device
    self.commandQueue = commandQueue
    self.commandBuffer = commandBuffer
    self.sharedEvent = sharedEvent
    sharedEvent.signaledValue = 0
    
    for _ in 0..<Self.maxFramesInFlight {
      guard let allocator = device.makeCommandAllocator(),
            let uniformBuf = device.makeBuffer(length: 4096, options: .storageModeShared) else {
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
    
    setupPipelines()
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
    for buf in uniformBuffers {
      residencySet.addAllocation(buf)
    }
    residencySet.commit()
    
    commandQueue.addResidencySet(residencySet)
  }
  
  private func setupPipelines() {
    guard let library = device.makeDefaultLibrary() else { return }
    
    func makePipeline(_ name: String) -> MTLComputePipelineState? {
      guard let function = library.makeFunction(name: name) else { return nil }
      return try? device.makeComputePipelineState(function: function)
    }
    
    splatPipeline = makePipeline("fluidSplat")
    advectPipeline = makePipeline("fluidAdvect")
    divergencePipeline = makePipeline("fluidDivergence")
    jacobiPipeline = makePipeline("fluidJacobi")
    gradientSubtractPipeline = makePipeline("fluidGradientSubtract")
    blurHPipeline = makePipeline("fluidBlurH")
    blurVPipeline = makePipeline("fluidBlurV")
    renderPipeline = makePipeline("fluidRender")
  }
  
  private func setupTextures() {
    velocityA = makeTexture(format: .rg16Float)
    velocityB = makeTexture(format: .rg16Float)
    pressure = makeTexture(format: .r16Float)
    pressureTemp = makeTexture(format: .r16Float)
    divergenceTexture = makeTexture(format: .r16Float)
    dyeA = makeTexture(format: .rgba16Float)
    dyeB = makeTexture(format: .rgba16Float)
  }
  
  private func makeTexture(format: MTLPixelFormat) -> MTLTexture? {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: format,
      width: gridSize,
      height: gridSize,
      mipmapped: false
    )
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private
    return device.makeTexture(descriptor: desc)
  }
  
  func ensureOutputTexture(width: Int, height: Int) {
    if let existing = outputTexture,
       existing.width == width, existing.height == height {
      return
    }
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
    desc.storageMode = .private
    outputTexture = device.makeTexture(descriptor: desc)
    
    if let outputTexture {
      residencySet.addAllocation(outputTexture)
      residencySet.commit()
    }
  }
  
  private func writeUniform<T>(_ value: T) -> MTLGPUAddress {
    let aligned = (uniformOffset + 15) & ~15
    (currentUniformBuffer.contents() + aligned).storeBytes(of: value, as: T.self)
    let addr = currentUniformBuffer.gpuAddress + MTLGPUAddress(aligned)
    uniformOffset = aligned + MemoryLayout<T>.size
    return addr
  }
  
  func update(bass: Float, mid: Float, high: Float, drawable: CAMetalDrawable) {
    frameNumber += 1
    let frameIndex = Int(frameNumber % Self.maxFramesInFlight)
    
    // Wait only for the frame that previously used this allocator/buffer slot.
    // For the first maxFramesInFlight frames, the wait value is <= 0 (already signaled).
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
    
    injectAudioSplats(encoder: encoder, bass: bass, mid: mid, high: high)
    
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    advect(encoder: encoder,
           velocityIn: velocityA, fieldIn: velocityA, fieldOut: velocityB,
           dissipation: velocityDissipation)
    swap(&velocityA, &velocityB)
    
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    computeDivergence(encoder: encoder)
    
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    for _ in 0..<jacobiIterations {
      jacobiIteration(encoder: encoder)
      swap(&pressure, &pressureTemp)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
    
    gradientSubtract(encoder: encoder)
    
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    advect(encoder: encoder,
           velocityIn: velocityA, fieldIn: dyeA, fieldOut: dyeB,
           dissipation: dyeDissipation)
    swap(&dyeA, &dyeB)
    
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    blurDyeH(encoder: encoder)
    swap(&dyeA, &dyeB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    blurDyeV(encoder: encoder)
    swap(&dyeA, &dyeB)
    
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    if let output = outputTexture {
      render(encoder: encoder, output: output)
    }
    
    if let output = outputTexture {
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .blit)
      
      let srcSize = MTLSize(
        width: min(output.width, drawable.texture.width),
        height: min(output.height, drawable.texture.height),
        depth: 1
      )
      encoder.copy(
        sourceTexture: output,
        sourceSlice: 0,
        sourceLevel: 0,
        sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
        sourceSize: srcSize,
        destinationTexture: drawable.texture,
        destinationSlice: 0,
        destinationLevel: 0,
        destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
      )
    }
    
    encoder.endEncoding()
    commandBuffer.endCommandBuffer()
    
    commandQueue.waitForDrawable(drawable)
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: frameNumber)
    commandQueue.signalDrawable(drawable)
    drawable.present()
  }
  
  private func injectAudioSplats(encoder: any MTL4ComputeCommandEncoder,
                                 bass: Float, mid: Float, high: Float) {
    let center = Float(gridSize) / 2.0
    let audioEnergy = (bass + mid + high) / 3.0
    
    if bass > 0.01 {
      let angle = time * 0.5
      let forceX = cos(angle) * bass * 450.0
      let forceY = sin(angle) * bass * 450.0
      let offset = bass * 120.0
      let splatPos = SIMD2<Float>(center + cos(angle) * offset, center + sin(angle) * offset)
      
      splatForce(encoder: encoder, pos: splatPos,
                 force: SIMD3<Float>(forceX, forceY, 0), radius: 150.0 + bass * 90.0)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
      
      let dyeColor = SIMD3<Float>(bass * 1.5, bass * 0.3, bass * 0.1)
      splatDye(encoder: encoder, pos: splatPos,
               color: dyeColor, radius: 120.0 + bass * 60.0)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
    
    if mid > 0.01 {
      for i in 0..<3 {
        let angle = time * 1.2 + Float(i) * 2.094
        let orbitRadius: Float = 300.0 + mid * 120.0
        let splatPos = SIMD2<Float>(center + cos(angle) * orbitRadius,
                                     center + sin(angle) * orbitRadius)
        let tangentX = -sin(angle) * mid * 270.0
        let tangentY = cos(angle) * mid * 270.0
        
        splatForce(encoder: encoder, pos: splatPos,
                   force: SIMD3<Float>(tangentX, tangentY, 0), radius: 90.0)
        encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
        
        let hueOffset = Float(i) * 0.33
        let dyeColor = SIMD3<Float>(mid * 0.2 + hueOffset * 0.3,
                                     mid * 0.8,
                                     mid * 1.2)
        splatDye(encoder: encoder, pos: splatPos,
                 color: dyeColor, radius: 72.0)
        encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
      }
    }
    
    if high > 0.05 {
      for i in 0..<4 {
        let hashAngle = time * 3.0 + Float(i) * 1.57 + sin(time * 2.3 + Float(i)) * 2.0
        let hashRadius = 180.0 + sin(time * 1.7 + Float(i) * 3.0) * 240.0
        let splatPos = SIMD2<Float>(center + cos(hashAngle) * Float(hashRadius),
                                     center + sin(hashAngle) * Float(hashRadius))
        
        let sparkForce = high * 135.0
        let forceDir = SIMD3<Float>(cos(hashAngle + 1.5) * sparkForce,
                                     sin(hashAngle + 1.5) * sparkForce, 0)
        splatForce(encoder: encoder, pos: splatPos,
                   force: forceDir, radius: 48.0)
        encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
        
        let dyeColor = SIMD3<Float>(high * 0.5 + audioEnergy * 0.5,
                                     high * 0.7,
                                     high * 1.5)
        splatDye(encoder: encoder, pos: splatPos,
                 color: dyeColor, radius: 36.0)
        encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
      }
    }
  }
  
}

extension NavierStokesRenderer {
  private func splatForce(encoder: any MTL4ComputeCommandEncoder, pos: SIMD2<Float>,
                          force: SIMD3<Float>, radius: Float) {
    encoder.setComputePipelineState(splatPipeline)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setAddress(writeUniform(pos), index: 0)
    argumentTable.setAddress(writeUniform(force), index: 1)
    argumentTable.setAddress(writeUniform(radius), index: 2)
    dispatchGrid(encoder: encoder, pipeline: splatPipeline)
  }
  
  private func splatDye(encoder: any MTL4ComputeCommandEncoder, pos: SIMD2<Float>,
                        color: SIMD3<Float>, radius: Float) {
    encoder.setComputePipelineState(splatPipeline)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setAddress(writeUniform(pos), index: 0)
    argumentTable.setAddress(writeUniform(color), index: 1)
    argumentTable.setAddress(writeUniform(radius), index: 2)
    dispatchGrid(encoder: encoder, pipeline: splatPipeline)
  }
  
  private func advect(encoder: any MTL4ComputeCommandEncoder,
                      velocityIn: MTLTexture, fieldIn: MTLTexture, fieldOut: MTLTexture,
                      dissipation: Float) {
    encoder.setComputePipelineState(advectPipeline)
    argumentTable.setTexture(velocityIn.gpuResourceID, index: 0)
    argumentTable.setTexture(fieldIn.gpuResourceID, index: 1)
    argumentTable.setTexture(fieldOut.gpuResourceID, index: 2)
    
    let dtVal = dt * 40.0
    argumentTable.setAddress(writeUniform(dtVal), index: 0)
    argumentTable.setAddress(writeUniform(dissipation), index: 1)
    
    dispatchGrid(encoder: encoder, pipeline: advectPipeline)
  }
  
  private func computeDivergence(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(divergencePipeline)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(divergenceTexture.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder, pipeline: divergencePipeline)
  }
  
  private func jacobiIteration(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(jacobiPipeline)
    argumentTable.setTexture(pressure.gpuResourceID, index: 0)
    argumentTable.setTexture(divergenceTexture.gpuResourceID, index: 1)
    argumentTable.setTexture(pressureTemp.gpuResourceID, index: 2)
    
    dispatchGrid(encoder: encoder, pipeline: jacobiPipeline)
  }
  
  private func gradientSubtract(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(gradientSubtractPipeline)
    argumentTable.setTexture(pressure.gpuResourceID, index: 0)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder, pipeline: gradientSubtractPipeline)
  }
  
  private func blurDyeH(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(blurHPipeline)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder, pipeline: blurHPipeline)
  }
  
  private func blurDyeV(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(blurVPipeline)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder, pipeline: blurVPipeline)
  }
  
  private func render(encoder: any MTL4ComputeCommandEncoder, output: MTLTexture) {
    encoder.setComputePipelineState(renderPipeline)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(output.gpuResourceID, index: 1)
    
    let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
    let threadGroups = MTLSize(
      width: (output.width + 15) / 16,
      height: (output.height + 15) / 16,
      depth: 1
    )
    encoder.dispatchThreadgroups(threadgroupsPerGrid: threadGroups,
                                threadsPerThreadgroup: threadGroupSize)
  }
  
  private func dispatchGrid(encoder: any MTL4ComputeCommandEncoder,
                            pipeline: MTLComputePipelineState) {
    let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
    let threadGroups = MTLSize(
      width: (gridSize + 15) / 16,
      height: (gridSize + 15) / 16,
      depth: 1
    )
    encoder.dispatchThreadgroups(threadgroupsPerGrid: threadGroups,
                                threadsPerThreadgroup: threadGroupSize)
  }
}
