//
//  NavierStokesRenderer+Setup.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import Metal
import os

extension NavierStokesRenderer {
  struct Pipelines {
    let splatBatch: MTLComputePipelineState
    let diffuse: MTLComputePipelineState
    let advect: MTLComputePipelineState
    let covectorAdvect: MTLComputePipelineState
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
    guard let library = device.makeDefaultLibrary() else {
      logger.error("Failed to create default Metal library")
      return nil
    }
    
    func makePipeline(_ name: String) -> MTLComputePipelineState? {
      let functionDesc = MTL4LibraryFunctionDescriptor()
      functionDesc.name = name
      functionDesc.library = library
      let pipelineDesc = MTL4ComputePipelineDescriptor()
      pipelineDesc.computeFunctionDescriptor = functionDesc
      do {
        return try compiler.makeComputePipelineState(descriptor: pipelineDesc)
      } catch {
        logger.error("Failed to create pipeline '\(name)': \(error.localizedDescription)")
        return nil
      }
    }
    
    guard let splatBatch = makePipeline("fluidSplatBatch"),
          let diffuse = makePipeline("fluidDiffuse"),
          let advect = makePipeline("fluidAdvect"),
          let covectorAdvect = makePipeline("fluidAdvectCovector"),
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
                     covectorAdvect: covectorAdvect,
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
    func makeTexture(format: MTLPixelFormat, label: String,
                     usage: MTLTextureUsage = [.shaderRead, .shaderWrite]) -> MTLTexture? {
      let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: format, width: gridSize, height: gridSize, mipmapped: false
      )
      desc.usage = usage
      desc.storageMode = .private
      guard let texture = device.makeTexture(descriptor: desc) else {
        logger.error("Failed to create texture '\(label)'")
        return nil
      }
      return texture
    }
    
    guard let velocityA = makeTexture(format: .rg16Float, label: "velocityA"),
          let velocityB = makeTexture(format: .rg16Float, label: "velocityB"),
          let pressure = makeTexture(format: .r16Float, label: "pressure"),
          let pressureTemp = makeTexture(format: .r16Float, label: "pressureTemp"),
          let divergence = makeTexture(format: .r16Float, label: "divergence"),
          let dyeA = makeTexture(format: .rgba16Float, label: "dyeA"),
          let dyeB = makeTexture(format: .rgba16Float, label: "dyeB"),
          let bloomA = makeTexture(format: .rgba16Float, label: "bloomA"),
          let bloomB = makeTexture(format: .rgba16Float, label: "bloomB") else {
      return nil
    }
    
    return Textures(velocityA: velocityA, velocityB: velocityB,
                    pressure: pressure, pressureTemp: pressureTemp,
                    divergence: divergence, dyeA: dyeA, dyeB: dyeB,
                    bloomA: bloomA, bloomB: bloomB)
  }
}
