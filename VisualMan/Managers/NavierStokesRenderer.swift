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
  
  let gridSize: Int = 1024
  
  private var splatPipeline: MTLComputePipelineState!
  private var diffusePipeline: MTLComputePipelineState!
  private var advectPipeline: MTLComputePipelineState!
  private var vorticityPipeline: MTLComputePipelineState!
  private var vorticityForcePipeline: MTLComputePipelineState!
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
  private var vorticityTexture: MTLTexture!
  
  var time: Float = 0
  private let dt: Float = 1.0 / 60.0
  var prevBass: Float = 0
  var prevMid: Float = 0
  private let velocityDissipation: Float = 0.99
  private let dyeDissipation: Float = 0.98
  private let jacobiIterations: Int = 10
  private let viscosity: Float = 0.0002
  private let diffuseIterations: Int = 4
  private let vorticityStrength: Float = 1.5
  
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
    residencySet.addAllocation(vorticityTexture!)
    
    for buf in uniformBuffers { residencySet.addAllocation(buf) }
    
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
    velocityA = makeTexture(format: .rg16Float)
    velocityB = makeTexture(format: .rg16Float)
    pressure = makeTexture(format: .r16Float)
    pressureTemp = makeTexture(format: .r16Float)
    divergenceTexture = makeTexture(format: .r16Float)
    dyeA = makeTexture(format: .rgba16Float)
    dyeB = makeTexture(format: .rgba16Float)
    vorticityTexture = makeTexture(format: .r16Float)
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
  
  private func writeUniform<T>(_ value: T) -> MTLGPUAddress {
    let aligned = (uniformOffset + 15) & ~15
    (currentUniformBuffer.contents() + aligned).storeBytes(of: value, as: T.self)
    let addr = currentUniformBuffer.gpuAddress + MTLGPUAddress(aligned)
    uniformOffset = aligned + MemoryLayout<T>.size
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
    applyVorticityForce(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    advect(encoder: encoder, velocityIn: velocityA, fieldIn: velocityA,
           fieldOut: velocityB, dissipation: velocityDissipation)
    swap(&velocityA, &velocityB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    project(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    advect(encoder: encoder, velocityIn: velocityA, fieldIn: dyeA,
           fieldOut: dyeB, dissipation: dyeDissipation)
    swap(&dyeA, &dyeB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    blurDyeH(encoder: encoder)
    swap(&dyeA, &dyeB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    blurDyeV(encoder: encoder)
    swap(&dyeA, &dyeB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    render(encoder: encoder, output: output)
  }
  
}

extension NavierStokesRenderer {
  func splatForce(encoder: any MTL4ComputeCommandEncoder,
                  pos: SIMD2<Float>,
                  force: SIMD3<Float>,
                  radius: Float) {
    encoder.setComputePipelineState(splatPipeline)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setAddress(writeUniform(pos), index: 0)
    argumentTable.setAddress(writeUniform(force), index: 1)
    argumentTable.setAddress(writeUniform(radius), index: 2)
    dispatchGrid(encoder: encoder)
  }
  
  func splatDye(encoder: any MTL4ComputeCommandEncoder,
                pos: SIMD2<Float>,
                color: SIMD3<Float>,
                radius: Float) {
    encoder.setComputePipelineState(splatPipeline)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setAddress(writeUniform(pos), index: 0)
    argumentTable.setAddress(writeUniform(color), index: 1)
    argumentTable.setAddress(writeUniform(radius), index: 2)
    dispatchGrid(encoder: encoder)
  }
  
  private func advect(encoder: any MTL4ComputeCommandEncoder,
                      velocityIn: MTLTexture,
                      fieldIn: MTLTexture,
                      fieldOut: MTLTexture,
                      dissipation: Float) {
    encoder.setComputePipelineState(advectPipeline)
    argumentTable.setTexture(velocityIn.gpuResourceID, index: 0)
    argumentTable.setTexture(fieldIn.gpuResourceID, index: 1)
    argumentTable.setTexture(fieldOut.gpuResourceID, index: 2)
    
    let dtVal = dt * 40.0
    argumentTable.setAddress(writeUniform(dtVal), index: 0)
    argumentTable.setAddress(writeUniform(dissipation), index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  private func computeVorticity(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(vorticityPipeline)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(vorticityTexture.gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder)
  }
  
  private func applyVorticityForce(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(vorticityForcePipeline)
    argumentTable.setTexture(vorticityTexture.gpuResourceID, index: 0)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 1)
    argumentTable.setAddress(writeUniform(vorticityStrength), index: 0)
    dispatchGrid(encoder: encoder)
  }
  
  private func diffuseField(encoder: any MTL4ComputeCommandEncoder,
                            fieldA: inout MTLTexture!,
                            fieldB: inout MTLTexture!) {
    let alpha = viscosity * dt * Float(gridSize * gridSize)
    let rBeta = 1.0 / (1.0 + 4.0 * alpha)
    
    for _ in 0..<diffuseIterations {
      encoder.setComputePipelineState(diffusePipeline)
      argumentTable.setTexture(fieldA.gpuResourceID, index: 0)
      argumentTable.setTexture(fieldB.gpuResourceID, index: 1)
      argumentTable.setAddress(writeUniform(alpha), index: 0)
      argumentTable.setAddress(writeUniform(rBeta), index: 1)
      dispatchGrid(encoder: encoder)
      swap(&fieldA, &fieldB)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
  }
  
  private func project(encoder: any MTL4ComputeCommandEncoder) {
    computeDivergence(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    for _ in 0..<jacobiIterations {
      jacobiIteration(encoder: encoder)
      swap(&pressure, &pressureTemp)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
    
    gradientSubtract(encoder: encoder)
  }
  
  private func computeDivergence(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(divergencePipeline)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(divergenceTexture.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  private func jacobiIteration(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(jacobiPipeline)
    argumentTable.setTexture(pressure.gpuResourceID, index: 0)
    argumentTable.setTexture(divergenceTexture.gpuResourceID, index: 1)
    argumentTable.setTexture(pressureTemp.gpuResourceID, index: 2)
    
    dispatchGrid(encoder: encoder)
  }
  
  private func gradientSubtract(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(gradientSubtractPipeline)
    argumentTable.setTexture(pressure.gpuResourceID, index: 0)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  private func blurDyeH(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(blurHPipeline)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  private func blurDyeV(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(blurVPipeline)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  private func render(encoder: any MTL4ComputeCommandEncoder, output: MTLTexture) {
    encoder.setComputePipelineState(renderPipeline)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(output.gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder, width: output.width, height: output.height)
  }
  
  private func dispatchGrid(encoder: any MTL4ComputeCommandEncoder, width: Int? = nil, height: Int? = nil) {
    let w = width ?? gridSize
    let h = height ?? gridSize
    let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
    let threadGroups = MTLSize(
      width: (w + 15) / 16,
      height: (h + 15) / 16,
      depth: 1
    )
    encoder.dispatchThreadgroups(threadgroupsPerGrid: threadGroups,
                                threadsPerThreadgroup: threadGroupSize)
  }
}
