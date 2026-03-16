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
  
  private var time: Float = 0
  private let dt: Float = 1.0 / 60.0
  private let velocityDissipation: Float = 0.99
  private let dyeDissipation: Float = 0.98
  private let jacobiIterations: Int = 15
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
  
  func update(bass: Float, mid: Float, high: Float, drawable: CAMetalDrawable) {
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
    
    injectAudioSplats(encoder: encoder, bass: bass, mid: mid, high: high)
    
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    advect(encoder: encoder,
           velocityIn: velocityA, fieldIn: velocityA, fieldOut: velocityB,
           dissipation: velocityDissipation)
    swap(&velocityA, &velocityB)
    
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    computeVorticity(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    applyVorticityForce(encoder: encoder)
    
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
    
    render(encoder: encoder, output: drawable.texture)
    
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
    let s = Float(gridSize) / 1536.0
    let audioEnergy = (bass + mid + high) / 3.0
    
    let vortexAngle = time * 0.3
    let vortexR: Float = 80.0 * s
    let vortexStrength: Float = 30.0 * s * (0.3 + audioEnergy * 0.7)
    for i in 0..<2 {
      if i > 0 {
        encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
      }
      let a = vortexAngle + Float(i) * .pi
      let pos = SIMD2<Float>(center + cos(a) * vortexR, center + sin(a) * vortexR)
      let tangent = SIMD3<Float>(-sin(a) * vortexStrength, cos(a) * vortexStrength, 0)
      splatForce(encoder: encoder, pos: pos, force: tangent, radius: 100.0 * s)
    }

    let hue = fmod(time * 0.1, 1.0)
    let ambientColor = SIMD3<Float>(
      0.4 + 0.25 * sin(hue * .pi * 2.0),
      0.2 + 0.25 * sin(hue * .pi * 2.0 + 2.094),
      0.3 + 0.25 * sin(hue * .pi * 2.0 + 4.189)
    )
    splatDye(encoder: encoder, pos: SIMD2<Float>(center, center),
             color: ambientColor * (0.5 + audioEnergy * 0.5), radius: 90.0 * s)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    if bass > 0.01 {
      let angle = time * 0.5
      let pulseR: Float = 100.0 * s + bass * 80.0 * s
      let pulsePos = SIMD2<Float>(center + cos(angle) * pulseR * 0.3,
                                   center + sin(angle) * pulseR * 0.3)
      
      let radialX = cos(angle) * bass * 280.0 * s
      let radialY = sin(angle) * bass * 280.0 * s
      splatForce(encoder: encoder, pos: pulsePos,
                 force: SIMD3<Float>(radialX, radialY, 0), radius: (100.0 + bass * 50.0) * s)

      let bassHue = fmod(time * 0.15, 1.0)
      let dyeColor = SIMD3<Float>(
        bass * (2.0 + 0.5 * sin(bassHue * .pi * 2.0)),
        bass * (0.6 + 0.6 * sin(bassHue * .pi * 2.0 + 1.0)),
        bass * (0.2 + 0.5 * sin(bassHue * .pi * 2.0 + 2.5))
      )
      splatDye(encoder: encoder, pos: pulsePos,
               color: dyeColor, radius: (80.0 + bass * 40.0) * s)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
    
    if mid > 0.01 {
      for i in 0..<3 {
        let angle = time * 0.8 + Float(i) * 2.094
        let orbitR = (250.0 + mid * 100.0) * s
        let pos = SIMD2<Float>(center + cos(angle) * orbitR,
                                center + sin(angle) * orbitR)
        let tangentX = -sin(angle) * mid * 200.0 * s
        let tangentY = cos(angle) * mid * 200.0 * s
        splatForce(encoder: encoder, pos: pos,
                   force: SIMD3<Float>(tangentX, tangentY, 0), radius: 70.0 * s)
        encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
        
        let counterAngle = angle + 0.4
        let counterR = orbitR * 0.6
        let counterPos = SIMD2<Float>(center + cos(counterAngle) * counterR,
                                       center + sin(counterAngle) * counterR)
        splatForce(encoder: encoder, pos: counterPos,
                   force: SIMD3<Float>(-tangentX * 0.5, -tangentY * 0.5, 0), radius: 50.0 * s)
        
        let midHue = fmod(time * 0.12 + Float(i) * 0.33, 1.0)
        let dyeColor = SIMD3<Float>(
          mid * (0.5 + 0.5 * sin(midHue * .pi * 2.0)),
          mid * (1.0 + 0.6 * sin(midHue * .pi * 2.0 + 2.0)),
          mid * (1.5 + 0.5 * sin(midHue * .pi * 2.0 + 4.0))
        )
        splatDye(encoder: encoder, pos: pos, color: dyeColor, radius: 55.0 * s)
        encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
      }
    }
    
    if high > 0.05 {
      for i in 0..<4 {
        let hashAngle = time * 2.5 + Float(i) * 1.57 + sin(time * 1.8 + Float(i)) * 1.5
        let hashRadius = (150.0 + sin(time * 1.3 + Float(i) * 2.7) * 200.0) * s
        let pos = SIMD2<Float>(center + cos(hashAngle) * Float(hashRadius),
                                center + sin(hashAngle) * Float(hashRadius))
        
        let sparkForce = high * 80.0 * s
        let forceDir = SIMD3<Float>(cos(hashAngle + 1.5) * sparkForce,
                                     sin(hashAngle + 1.5) * sparkForce, 0)
        splatForce(encoder: encoder, pos: pos, force: forceDir, radius: 35.0 * s)
        
        let sparkHue = fmod(time * 0.2 + Float(i) * 0.25, 1.0)
        let dyeColor = SIMD3<Float>(
          high * (0.8 + 0.8 * sin(sparkHue * .pi * 2.0)),
          high * (0.6 + 1.0 * sin(sparkHue * .pi * 2.0 + 2.094)),
          high * (1.0 + 1.0 * sin(sparkHue * .pi * 2.0 + 4.189))
        )
        splatDye(encoder: encoder, pos: pos, color: dyeColor, radius: 26.0 * s)
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
  
  private func computeVorticity(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(vorticityPipeline)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(vorticityTexture.gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder, pipeline: vorticityPipeline)
  }
  
  private func applyVorticityForce(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(vorticityForcePipeline)
    argumentTable.setTexture(vorticityTexture.gpuResourceID, index: 0)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 1)
    argumentTable.setAddress(writeUniform(vorticityStrength), index: 0)
    dispatchGrid(encoder: encoder, pipeline: vorticityForcePipeline)
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
