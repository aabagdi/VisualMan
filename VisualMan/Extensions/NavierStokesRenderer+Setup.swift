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
    let curl: MTLComputePipelineState
    let vorticityConfinement: MTLComputePipelineState
    let macCormackCorrect: MTLComputePipelineState
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
          let clearRGBA = makePipeline("fluidClearRGBA"),
          let curl = makePipeline("fluidCurl"),
          let vorticityConfinement = makePipeline("fluidVorticityConfinement"),
          let macCormackCorrect = makePipeline("fluidMacCormackCorrect") else {
      return nil
    }

    return Pipelines(splatBatch: splatBatch, advect: advect,
                     psiInit: psiInit, psiAdvect: psiAdvect,
                     covectorPullback: covectorPullback, copyRG: copyRG,
                     divergence: divergence, jacobiRedBlack: jacobiRedBlack,
                     gradientSubtract: gradientSubtract, blurH: blurH,
                     blurV: blurV, bloomThresholdBlurH: bloomThresholdBlurH,
                     render: render, clearRG: clearRG, clearRGBA: clearRGBA,
                     curl: curl, vorticityConfinement: vorticityConfinement,
                     macCormackCorrect: macCormackCorrect)
  }

  struct Textures {
    let velocityA: MTLTexture
    let velocityB: MTLTexture
    let pressure: MTLTexture
    let divergence: MTLTexture
    let dyeA: MTLTexture
    let dyeB: MTLTexture
    let dyeC: MTLTexture
    let bloomA: MTLTexture
    let bloomB: MTLTexture
    let bloomMidA: MTLTexture
    let bloomMidB: MTLTexture
    let bloomLoA: MTLTexture
    let bloomLoB: MTLTexture
    let psiA: MTLTexture
    let psiB: MTLTexture
    let u0: MTLTexture
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
    desc.maxTextureBindCount = 7
    desc.maxBufferBindCount = 3
    do {
      return try device.makeArgumentTable(descriptor: desc)
    } catch {
      logger.error("Failed to create argument table: \(error.localizedDescription)")
      return nil
    }
  }

  static func createResidencySet(device: MTLDevice) -> MTLResidencySet? {
    let desc = MTLResidencySetDescriptor()
    desc.initialCapacity = 16
    return try? device.makeResidencySet(descriptor: desc)
  }

  static let bloomSize: Int = 256
  static let bloomSizeMid: Int = 128
  static let bloomSizeLo: Int = 64

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
          let dyeC = makeTexture(format: .rgba16Float, label: "dyeC"),
          let bloomA = makeTexture(format: .rgba16Float, label: "bloomA",
                                   width: bloomSize, height: bloomSize),
          let bloomB = makeTexture(format: .rgba16Float, label: "bloomB",
                                   width: bloomSize, height: bloomSize),
          let bloomMidA = makeTexture(format: .rgba16Float, label: "bloomMidA",
                                      width: bloomSizeMid, height: bloomSizeMid),
          let bloomMidB = makeTexture(format: .rgba16Float, label: "bloomMidB",
                                      width: bloomSizeMid, height: bloomSizeMid),
          let bloomLoA = makeTexture(format: .rgba16Float, label: "bloomLoA",
                                     width: bloomSizeLo, height: bloomSizeLo),
          let bloomLoB = makeTexture(format: .rgba16Float, label: "bloomLoB",
                                     width: bloomSizeLo, height: bloomSizeLo),
          let psiA = makeTexture(format: .rg16Float, label: "psiA"),
          let psiB = makeTexture(format: .rg16Float, label: "psiB"),
          let u0 = makeTexture(format: .rg16Float, label: "u0") else {
      return nil
    }

    return Textures(velocityA: velocityA, velocityB: velocityB,
                    pressure: pressure,
                    divergence: divergence, dyeA: dyeA, dyeB: dyeB, dyeC: dyeC,
                    bloomA: bloomA, bloomB: bloomB,
                    bloomMidA: bloomMidA, bloomMidB: bloomMidB,
                    bloomLoA: bloomLoA, bloomLoB: bloomLoB,
                    psiA: psiA, psiB: psiB, u0: u0)
  }

  func warmUpGPU() {
    let allocator = commandAllocators[0]
    currentUniformBuffer = uniformBuffers[0]
    allocator.reset()
    uniformOffset = 0

    commandBuffer.beginCommandBuffer(allocator: allocator)
    commandBuffer.useResidencySet(residencySet)
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setArgumentTable(argumentTable)

    encoder.setComputePipelineState(pipelines.clearRG)
    for tex in [velocityA, velocityB, u0] {
      argumentTable.setTexture(tex.gpuResourceID, index: 0)
      dispatchGrid(encoder: encoder)
    }

    for tex in [pressure, divergenceTexture] {
      argumentTable.setTexture(tex.gpuResourceID, index: 0)
      dispatchGrid(encoder: encoder)
    }

    encoder.setComputePipelineState(pipelines.clearRGBA)
    for tex in [dyeA, dyeB, dyeC, bloomA, bloomB, bloomMidA, bloomMidB, bloomLoA, bloomLoB] {
      argumentTable.setTexture(tex.gpuResourceID, index: 0)
      dispatchGrid(encoder: encoder)
    }

    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(pipelines.psiInit)
    argumentTable.setTexture(psiA.gpuResourceID, index: 0)
    dispatchGrid(encoder: encoder)

    encoder.endEncoding()
    commandBuffer.endCommandBuffer()
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: 1)
    frameNumber = 1
  }

  func drainPendingTAAHistoryReleases() {
    guard !pendingTAAHistoryReleases.isEmpty else { return }
    let signaled = sharedEvent.signaledValue
    var removedAny = false
    pendingTAAHistoryReleases.removeAll { entry in
      if signaled >= entry.frame {
        residencySet.removeAllocation(entry.texture)
        removedAny = true
        return true
      }
      return false
    }
    if removedAny {
      residencySet.commit()
    }
  }

  func ensureTAAHistory(width: Int, height: Int) {
    drainPendingTAAHistoryReleases()

    if width == taaHistoryWidth && height == taaHistoryHeight && taaHistoryA != nil { return }

    let fenceFrame = frameNumber
    if let a = taaHistoryA {
      pendingTAAHistoryReleases.append((frame: fenceFrame, texture: a))
    }
    if let b = taaHistoryB {
      pendingTAAHistoryReleases.append((frame: fenceFrame, texture: b))
    }

    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private

    guard let a = device.makeTexture(descriptor: desc),
          let b = device.makeTexture(descriptor: desc) else {
      taaHistoryA = nil
      taaHistoryB = nil
      taaHistoryValid = false
      taaHistoryWidth = 0
      taaHistoryHeight = 0
      return
    }

    residencySet.addAllocation(a)
    residencySet.addAllocation(b)
    residencySet.commit()

    taaHistoryA = a
    taaHistoryB = b
    taaHistoryValid = false
    taaHistoryWidth = width
    taaHistoryHeight = height
  }

  func configureResidencySet() {
    residencySet.addAllocation(velocityA)
    residencySet.addAllocation(velocityB)
    residencySet.addAllocation(pressure)
    residencySet.addAllocation(divergenceTexture)
    residencySet.addAllocation(dyeA)
    residencySet.addAllocation(dyeB)
    residencySet.addAllocation(dyeC)
    residencySet.addAllocation(bloomA)
    residencySet.addAllocation(bloomB)
    residencySet.addAllocation(bloomMidA)
    residencySet.addAllocation(bloomMidB)
    residencySet.addAllocation(bloomLoA)
    residencySet.addAllocation(bloomLoB)
    residencySet.addAllocation(psiA)
    residencySet.addAllocation(psiB)
    residencySet.addAllocation(u0)

    for buf in uniformBuffers { residencySet.addAllocation(buf) }

    residencySet.commit()

    commandQueue.addResidencySet(residencySet)
  }
}
