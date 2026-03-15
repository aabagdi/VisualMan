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
  let commandQueue: MTLCommandQueue
  
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
  
  init?() {
    guard let device = MTLCreateSystemDefaultDevice(),
          let commandQueue = device.makeCommandQueue() else {
      return nil
    }
    self.device = device
    self.commandQueue = commandQueue
    
    setupPipelines()
    setupTextures()
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
  }
  
  func update(bass: Float, mid: Float, high: Float) {
    guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
    
    time += dt * (1.0 + bass * 0.5)
    
    injectAudioSplats(commandBuffer: commandBuffer, bass: bass, mid: mid, high: high)
    
    advect(commandBuffer: commandBuffer,
           velocityIn: velocityA, fieldIn: velocityA, fieldOut: velocityB,
           dissipation: velocityDissipation)
    swap(&velocityA, &velocityB)
    
    computeDivergence(commandBuffer: commandBuffer)
    
    for _ in 0..<jacobiIterations {
      jacobiIteration(commandBuffer: commandBuffer)
      swap(&pressure, &pressureTemp)
    }
    
    gradientSubtract(commandBuffer: commandBuffer)
    
    advect(commandBuffer: commandBuffer,
           velocityIn: velocityA, fieldIn: dyeA, fieldOut: dyeB,
           dissipation: dyeDissipation)
    swap(&dyeA, &dyeB)
    
    blurDyeH(commandBuffer: commandBuffer)
    swap(&dyeA, &dyeB)
    blurDyeV(commandBuffer: commandBuffer)
    swap(&dyeA, &dyeB)
    
    if let output = outputTexture {
      render(commandBuffer: commandBuffer, output: output)
    }
    
    commandBuffer.commit()
  }
  
  private func injectAudioSplats(commandBuffer: MTLCommandBuffer, bass: Float, mid: Float, high: Float) {
    let center = Float(gridSize) / 2.0
    let audioEnergy = (bass + mid + high) / 3.0
    
    if bass > 0.01 {
      let angle = time * 0.5
      let forceX = cos(angle) * bass * 450.0
      let forceY = sin(angle) * bass * 450.0
      let offset = bass * 120.0
      let splatPos = SIMD2<Float>(center + cos(angle) * offset, center + sin(angle) * offset)
      
      splatForce(commandBuffer: commandBuffer, pos: splatPos,
                 force: SIMD3<Float>(forceX, forceY, 0), radius: 150.0 + bass * 90.0)
      
      let dyeColor = SIMD3<Float>(bass * 1.5, bass * 0.3, bass * 0.1)
      splatDye(commandBuffer: commandBuffer, pos: splatPos,
               color: dyeColor, radius: 120.0 + bass * 60.0)
    }
    
    if mid > 0.01 {
      for i in 0..<3 {
        let angle = time * 1.2 + Float(i) * 2.094
        let orbitRadius: Float = 300.0 + mid * 120.0
        let splatPos = SIMD2<Float>(center + cos(angle) * orbitRadius,
                                     center + sin(angle) * orbitRadius)
        let tangentX = -sin(angle) * mid * 270.0
        let tangentY = cos(angle) * mid * 270.0
        
        splatForce(commandBuffer: commandBuffer, pos: splatPos,
                   force: SIMD3<Float>(tangentX, tangentY, 0), radius: 90.0)
        
        let hueOffset = Float(i) * 0.33
        let dyeColor = SIMD3<Float>(mid * 0.2 + hueOffset * 0.3,
                                     mid * 0.8,
                                     mid * 1.2)
        splatDye(commandBuffer: commandBuffer, pos: splatPos,
                 color: dyeColor, radius: 72.0)
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
        splatForce(commandBuffer: commandBuffer, pos: splatPos,
                   force: forceDir, radius: 48.0)
        
        let dyeColor = SIMD3<Float>(high * 0.5 + audioEnergy * 0.5,
                                     high * 0.7,
                                     high * 1.5)
        splatDye(commandBuffer: commandBuffer, pos: splatPos,
                 color: dyeColor, radius: 36.0)
      }
    }
  }
  
}

extension NavierStokesRenderer {
  private func splatForce(commandBuffer: MTLCommandBuffer, pos: SIMD2<Float>,
                          force: SIMD3<Float>, radius: Float) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setComputePipelineState(splatPipeline)
    encoder.setTexture(velocityA, index: 0)
    
    var point = pos
    var value = force
    var rad = radius
    encoder.setBytes(&point, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
    encoder.setBytes(&value, length: MemoryLayout<SIMD3<Float>>.size, index: 1)
    encoder.setBytes(&rad, length: MemoryLayout<Float>.size, index: 2)
    
    dispatchGrid(encoder: encoder, pipeline: splatPipeline)
    encoder.endEncoding()
  }
  
  private func splatDye(commandBuffer: MTLCommandBuffer, pos: SIMD2<Float>,
                        color: SIMD3<Float>, radius: Float) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setComputePipelineState(splatPipeline)
    encoder.setTexture(dyeA, index: 0)
    
    var point = pos
    var value = color
    var rad = radius
    encoder.setBytes(&point, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
    encoder.setBytes(&value, length: MemoryLayout<SIMD3<Float>>.size, index: 1)
    encoder.setBytes(&rad, length: MemoryLayout<Float>.size, index: 2)
    
    dispatchGrid(encoder: encoder, pipeline: splatPipeline)
    encoder.endEncoding()
  }
  
  private func advect(commandBuffer: MTLCommandBuffer,
                      velocityIn: MTLTexture, fieldIn: MTLTexture, fieldOut: MTLTexture,
                      dissipation: Float) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setComputePipelineState(advectPipeline)
    encoder.setTexture(velocityIn, index: 0)
    encoder.setTexture(fieldIn, index: 1)
    encoder.setTexture(fieldOut, index: 2)
    
    var dtVal = dt * 40.0
    var dissVal = dissipation
    encoder.setBytes(&dtVal, length: MemoryLayout<Float>.size, index: 0)
    encoder.setBytes(&dissVal, length: MemoryLayout<Float>.size, index: 1)
    
    dispatchGrid(encoder: encoder, pipeline: advectPipeline)
    encoder.endEncoding()
  }
  
  private func computeDivergence(commandBuffer: MTLCommandBuffer) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setComputePipelineState(divergencePipeline)
    encoder.setTexture(velocityA, index: 0)
    encoder.setTexture(divergenceTexture, index: 1)
    
    dispatchGrid(encoder: encoder, pipeline: divergencePipeline)
    encoder.endEncoding()
  }
  
  private func jacobiIteration(commandBuffer: MTLCommandBuffer) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setComputePipelineState(jacobiPipeline)
    encoder.setTexture(pressure, index: 0)
    encoder.setTexture(divergenceTexture, index: 1)
    encoder.setTexture(pressureTemp, index: 2)
    
    dispatchGrid(encoder: encoder, pipeline: jacobiPipeline)
    encoder.endEncoding()
  }
  
  private func gradientSubtract(commandBuffer: MTLCommandBuffer) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setComputePipelineState(gradientSubtractPipeline)
    encoder.setTexture(pressure, index: 0)
    encoder.setTexture(velocityA, index: 1)
    
    dispatchGrid(encoder: encoder, pipeline: gradientSubtractPipeline)
    encoder.endEncoding()
  }
  
  private func blurDyeH(commandBuffer: MTLCommandBuffer) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setComputePipelineState(blurHPipeline)
    encoder.setTexture(dyeA, index: 0)
    encoder.setTexture(dyeB, index: 1)
    
    dispatchGrid(encoder: encoder, pipeline: blurHPipeline)
    encoder.endEncoding()
  }
  
  private func blurDyeV(commandBuffer: MTLCommandBuffer) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setComputePipelineState(blurVPipeline)
    encoder.setTexture(dyeA, index: 0)
    encoder.setTexture(dyeB, index: 1)
    
    dispatchGrid(encoder: encoder, pipeline: blurVPipeline)
    encoder.endEncoding()
  }
  
  private func render(commandBuffer: MTLCommandBuffer, output: MTLTexture) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setComputePipelineState(renderPipeline)
    encoder.setTexture(dyeA, index: 0)
    encoder.setTexture(output, index: 1)
    
    let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
    let threadGroups = MTLSize(
      width: (output.width + 15) / 16,
      height: (output.height + 15) / 16,
      depth: 1
    )
    encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
    encoder.endEncoding()
  }
  
  private func dispatchGrid(encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState) {
    let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
    let threadGroups = MTLSize(
      width: (gridSize + 15) / 16,
      height: (gridSize + 15) / 16,
      depth: 1
    )
    encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
  }
}
