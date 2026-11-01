//
//  NavierStokesRenderer+Setup.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

#if !targetEnvironment(simulator)
import Metal
import os

extension NavierStokesRenderer {
  struct Pipelines {
    let splatBatch: MTLComputePipelineState
    let advect: MTLComputePipelineState
    let psiInit: MTLComputePipelineState
    let psiAdvect: MTLComputePipelineState
    let psiMacCormackCorrect: MTLComputePipelineState
    let covectorPullback: MTLComputePipelineState
    let copyRG: MTLComputePipelineState
    let divergence: MTLComputePipelineState
    let jacobiMerged: MTLComputePipelineState
    let gradientSubtract: MTLComputePipelineState
    let blurH: MTLComputePipelineState
    let blurV: MTLComputePipelineState
    let bloomThresholdBlurH: MTLComputePipelineState
    let bloomDownsample: MTLComputePipelineState
    let render: MTLComputePipelineState
    let clearRGBA: MTLComputePipelineState
    let vorticityConfinementMerged: MTLComputePipelineState
    let macCormackCorrect: MTLComputePipelineState
    let dyeDiffuse: MTLComputePipelineState
    let divergenceRHS: MTLComputePipelineState
    let mgSmooth: MTLComputePipelineState
    let mgRestrict: MTLComputePipelineState
    let mgProlong: MTLComputePipelineState
    let mgCoarseSolve: MTLComputePipelineState
    let viscosity: MTLComputePipelineState
    let resample: MTLComputePipelineState
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
    let bloomLoA: MTLTexture
    let psiA: MTLTexture
    let psiB: MTLTexture
    let psiC: MTLTexture
    let u0: MTLTexture
    let mgPressure: [MTLTexture]
    let mgRHS: [MTLTexture]
  }

  nonisolated static func createPipelines(device: MTLDevice, compiler: any MTL4Compiler) -> Pipelines? {
    guard let library = device.makeDefaultLibrary() else {
      logger.error("Failed to create default Metal library")
      return nil
    }

    let make = { (name: String) in Self.makePipeline(name, library: library, compiler: compiler) }

    guard let splatBatch = make("fluidSplatBatch"), let advect = make("fluidAdvect"),
          let psiInit = make("fluidPsiInit"), let psiAdvect = make("fluidPsiAdvect"),
          let psiMacCormackCorrect = make("fluidPsiMacCormackCorrect"),
          let covectorPullback = make("fluidCovectorPullback"),
          let copyRG = make("fluidCopyRG"), let divergence = make("fluidDivergence"),
          let jacobiMerged = make("fluidJacobiMerged"),
          let gradientSubtract = make("fluidGradientSubtract"),
          let blurH = make("fluidBlurH"), let blurV = make("fluidBlurV"),
          let bloomThresholdBlurH = make("fluidBloomThresholdBlurH"),
          let bloomDownsample = make("fluidBloomDownsample"),
          let render = make("fluidRender"),
          let clearRGBA = make("fluidClearRGBA"),
          let vorticityConfinementMerged = make("fluidVorticityConfinementMerged"),
          let macCormackCorrect = make("fluidMacCormackCorrect"),
          let dyeDiffuse = make("fluidDyeDiffuse"),
          let divergenceRHS = make("fluidDivergenceRHS"),
          let mgSmooth = make("fluidMGSmooth"),
          let mgRestrict = make("fluidMGRestrict"),
          let mgProlong = make("fluidMGProlong"),
          let mgCoarseSolve = make("fluidMGCoarseSolve"),
          let viscosity = make("fluidViscosity"),
          let resample = make("fluidResample") else {
      return nil
    }

    return Pipelines(splatBatch: splatBatch, advect: advect,
                     psiInit: psiInit, psiAdvect: psiAdvect,
                     psiMacCormackCorrect: psiMacCormackCorrect,
                     covectorPullback: covectorPullback, copyRG: copyRG,
                     divergence: divergence, jacobiMerged: jacobiMerged,
                     gradientSubtract: gradientSubtract, blurH: blurH,
                     blurV: blurV, bloomThresholdBlurH: bloomThresholdBlurH,
                     bloomDownsample: bloomDownsample,
                     render: render, clearRGBA: clearRGBA,
                     vorticityConfinementMerged: vorticityConfinementMerged,
                     macCormackCorrect: macCormackCorrect,
                     dyeDiffuse: dyeDiffuse,
                     divergenceRHS: divergenceRHS,
                     mgSmooth: mgSmooth,
                     mgRestrict: mgRestrict, mgProlong: mgProlong,
                     mgCoarseSolve: mgCoarseSolve,
                     viscosity: viscosity, resample: resample)
  }

  static func createArgumentTables(device: MTLDevice) -> [any MTL4ArgumentTable]? {
    let desc = MTL4ArgumentTableDescriptor()
    desc.maxTextureBindCount = 7
    desc.maxBufferBindCount = 4
    var tables = [any MTL4ArgumentTable]()
    for _ in 0..<maxFramesInFlight {
      do {
        tables.append(try device.makeArgumentTable(descriptor: desc))
      } catch {
        logger.error("Failed to create argument table: \(error.localizedDescription)")
        return nil
      }
    }
    return tables
  }

  static func createResidencySet(device: MTLDevice) -> MTLResidencySet? {
    let desc = MTLResidencySetDescriptor()
    desc.initialCapacity = 40
    do {
      return try device.makeResidencySet(descriptor: desc)
    } catch {
      logger.error("Failed to create residency set: \(error.localizedDescription)")
      return nil
    }
  }

  static let bloomSize: Int = 256
  static let bloomSizeMid: Int = 128
  static let bloomSizeLo: Int = 64

  static func createTextures(device: MTLDevice, width: Int, height: Int) -> Textures? {
    func makeTexture(format: MTLPixelFormat, label: String,
                     width: Int = width,
                     height: Int = height,
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
      texture.label = label
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
          let bloomLoA = makeTexture(format: .rgba16Float, label: "bloomLoA",
                                     width: bloomSizeLo, height: bloomSizeLo),
          let psiA = makeTexture(format: .rg32Float, label: "psiA"),
          let psiB = makeTexture(format: .rg32Float, label: "psiB"),
          let psiC = makeTexture(format: .rg32Float, label: "psiC"),
          let u0 = makeTexture(format: .rg16Float, label: "u0") else {
      return nil
    }

    guard let (mgPressure, mgRHS) = createMultigridLevels(device: device, width: width, height: height) else {
      return nil
    }

    return Textures(velocityA: velocityA, velocityB: velocityB,
                    pressure: pressure,
                    divergence: divergence, dyeA: dyeA, dyeB: dyeB, dyeC: dyeC,
                    bloomA: bloomA, bloomB: bloomB,
                    bloomMidA: bloomMidA, bloomLoA: bloomLoA,
                    psiA: psiA, psiB: psiB, psiC: psiC, u0: u0,
                    mgPressure: mgPressure, mgRHS: mgRHS)
  }

  static func createMultigridLevels(device: MTLDevice,
                                    width: Int,
                                    height: Int) -> (pressure: [MTLTexture], rhs: [MTLTexture])? {
    var mgPressure = [MTLTexture]()
    var mgRHS = [MTLTexture]()
    var w = width
    var h = height
    while true {
      let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .r32Float, width: w, height: h, mipmapped: false
      )
      desc.usage = [.shaderRead, .shaderWrite]
      desc.storageMode = .private
      guard let pressure = device.makeTexture(descriptor: desc),
            let rhs = device.makeTexture(descriptor: desc) else {
        logger.error("Failed to create multigrid level \(w)x\(h)")
        return nil
      }
      pressure.label = "mgPressure\(w)x\(h)"
      rhs.label = "mgRHS\(w)x\(h)"
      mgPressure.append(pressure)
      mgRHS.append(rhs)
      if w * h <= multigridCoarseCells || (w <= 2 && h <= 2) { break }
      w = (w + 1) / 2
      h = (h + 1) / 2
    }
    return (mgPressure, mgRHS)
  }

  func warmUpGPU() {
    let warmupFrame: UInt64 = 1
    let frameIndex = Int(warmupFrame % Self.maxFramesInFlight)
    let allocator = commandAllocators[frameIndex]
    currentUniformBuffer = uniformBuffers[frameIndex]
    allocator.reset()
    uniformOffset = 0

    commandBuffer.beginCommandBuffer(allocator: allocator)
    commandBuffer.useResidencySet(residencySet)
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setArgumentTable(argumentTable)

    encoder.setComputePipelineState(pipelines.clearRGBA)
    for tex in allSimulationTextures {
      argumentTable.setTexture(tex.gpuResourceID, index: 0)
      dispatchGrid(encoder: encoder, width: tex.width, height: tex.height)
    }

    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(pipelines.psiInit)
    argumentTable.setTexture(psiA.gpuResourceID, index: 0)
    dispatchGrid(encoder: encoder)

    encoder.endEncoding()
    commandBuffer.endCommandBuffer()
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: warmupFrame)
    frameNumber = warmupFrame

    sharedEvent.wait(untilSignaledValue: warmupFrame, timeoutMS: 1000)
  }

  func drainPendingTAAHistoryReleases() {
    drainPendingReleases(&pendingTAAHistoryReleases)
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
    for tex in allSimulationTextures { residencySet.addAllocation(tex) }
    residencySet.addAllocation(stretchStatsBuffer)
    for buf in uniformBuffers { residencySet.addAllocation(buf) }

    residencySet.commit()

    commandQueue.addResidencySet(residencySet)
  }
}

#endif
