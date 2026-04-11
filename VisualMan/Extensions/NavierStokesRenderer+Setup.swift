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
    let advect: MTLComputePipelineState
    let psiInit: MTLComputePipelineState
    let psiAdvect: MTLComputePipelineState
    let covectorPullback: MTLComputePipelineState
    let copyRG: MTLComputePipelineState
    let divergence: MTLComputePipelineState
    let jacobiRedBlack: MTLComputePipelineState
    let gradientSubtract: MTLComputePipelineState
    let blurH: MTLComputePipelineState
    let blurV: MTLComputePipelineState
    let bloomThresholdBlurH: MTLComputePipelineState
    let render: MTLComputePipelineState
    let clearRG: MTLComputePipelineState
    let clearRGBA: MTLComputePipelineState
  }
  
  nonisolated static func createPipelines(device: MTLDevice, compiler: any MTL4Compiler) -> Pipelines? {
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
          let advect = makePipeline("fluidAdvect"),
          let psiInit = makePipeline("fluidPsiInit"),
          let psiAdvect = makePipeline("fluidPsiAdvect"),
          let covectorPullback = makePipeline("fluidCovectorPullback"),
          let copyRG = makePipeline("fluidCopyRG"),
          let divergence = makePipeline("fluidDivergence"),
          let jacobiRedBlack = makePipeline("fluidJacobiRedBlack"),
          let gradientSubtract = makePipeline("fluidGradientSubtract"),
          let blurH = makePipeline("fluidBlurH"),
          let blurV = makePipeline("fluidBlurV"),
          let bloomThresholdBlurH = makePipeline("fluidBloomThresholdBlurH"),
          let render = makePipeline("fluidRender"),
          let clearRG = makePipeline("fluidClearRG"),
          let clearRGBA = makePipeline("fluidClearRGBA") else {
      return nil
    }
    
    return Pipelines(splatBatch: splatBatch, advect: advect,
                     psiInit: psiInit, psiAdvect: psiAdvect,
                     covectorPullback: covectorPullback, copyRG: copyRG,
                     divergence: divergence, jacobiRedBlack: jacobiRedBlack,
                     gradientSubtract: gradientSubtract, blurH: blurH,
                     blurV: blurV, bloomThresholdBlurH: bloomThresholdBlurH,
                     render: render, clearRG: clearRG, clearRGBA: clearRGBA)
  }
  
  struct Textures {
    let velocityA: MTLTexture
    let velocityB: MTLTexture
    let pressure: MTLTexture
    let divergence: MTLTexture
    let dyeA: MTLTexture
    let dyeB: MTLTexture
    let bloomA: MTLTexture
    let bloomB: MTLTexture
    let psiA: MTLTexture
    let psiB: MTLTexture
    let u0: MTLTexture
  }
  
  static func createResidencySet(device: MTLDevice) -> MTLResidencySet? {
    let desc = MTLResidencySetDescriptor()
    desc.initialCapacity = 16
    return try? device.makeResidencySet(descriptor: desc)
  }

  static let bloomSize: Int = 256

  static func createTextures(device: MTLDevice) -> Textures? {
    func makeTexture(format: MTLPixelFormat, label: String,
                     width: Int = gridSize,
                     height: Int = gridSize,
                     usage: MTLTextureUsage = [.shaderRead, .shaderWrite]) -> MTLTexture? {
      let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: format, width: width, height: height, mipmapped: false
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
          let divergence = makeTexture(format: .r16Float, label: "divergence"),
          let dyeA = makeTexture(format: .rgba16Float, label: "dyeA"),
          let dyeB = makeTexture(format: .rgba16Float, label: "dyeB"),
          let bloomA = makeTexture(format: .rgba16Float, label: "bloomA",
                                   width: bloomSize, height: bloomSize),
          let bloomB = makeTexture(format: .rgba16Float, label: "bloomB",
                                   width: bloomSize, height: bloomSize),
          let psiA = makeTexture(format: .rg16Float, label: "psiA"),
          let psiB = makeTexture(format: .rg16Float, label: "psiB"),
          let u0 = makeTexture(format: .rg16Float, label: "u0") else {
      return nil
    }

    return Textures(velocityA: velocityA, velocityB: velocityB,
                    pressure: pressure,
                    divergence: divergence, dyeA: dyeA, dyeB: dyeB,
                    bloomA: bloomA, bloomB: bloomB,
                    psiA: psiA, psiB: psiB, u0: u0)
  }
}
