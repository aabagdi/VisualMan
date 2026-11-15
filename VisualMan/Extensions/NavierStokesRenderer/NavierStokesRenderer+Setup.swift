//
//  NavierStokesRenderer+Setup.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

#if !targetEnvironment(simulator)
import Metal
import CoreGraphics
import os

extension NavierStokesRenderer {
  struct MissingResource: Error { let name: String }

  struct Pipelines {
    let splatBatch: MTLComputePipelineState
    let tentFilter: MTLComputePipelineState
    let cloudDensity: MTLComputePipelineState
    let cloudLight: MTLComputePipelineState
    let psiInit: MTLComputePipelineState
    let psiAdvect: MTLComputePipelineState
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
    let buoyancy: MTLComputePipelineState
    let vortexField: MTLComputePipelineState
    let dyeMapReset: MTLComputePipelineState
    let dyeMapAccumulate: MTLComputePipelineState
    let dyeMapAdvance: MTLComputePipelineState
    let dyeMapLookup: MTLComputePipelineState
    let dyeMapError: MTLComputePipelineState
    let dyeMapCorrect: MTLComputePipelineState
    let dyeDiffuse: MTLComputePipelineState
    let divergenceRHS: MTLComputePipelineState
    let mgDescendDivergence: MTLComputePipelineState
    let mgDescendZero: MTLComputePipelineState
    let mgDescend: MTLComputePipelineState
    let mgAscend: MTLComputePipelineState
    let mgAscendProject: MTLComputePipelineState
    let mgCoarseSolve: MTLComputePipelineState
    let resample: MTLComputePipelineState
    let technicolorBakeLUT: MTLComputePipelineState

    nonisolated init(make: (String) -> MTLComputePipelineState?) throws(MissingResource) {
      func load(_ name: String) throws(MissingResource) -> MTLComputePipelineState {
        guard let pipeline = make(name) else { throw MissingResource(name: name) }
        return pipeline
      }

      splatBatch = try load("fluidSplatBatch")
      tentFilter = try load("fluidTentFilter")
      cloudDensity = try load("fluidCloudDensity")
      cloudLight = try load("fluidCloudLight")
      psiInit = try load("fluidPsiInit")
      psiAdvect = try load("fluidPsiAdvect")
      covectorPullback = try load("fluidCovectorPullback")
      copyRG = try load("fluidCopyRG")
      divergence = try load("fluidDivergence")
      jacobiMerged = try load("fluidJacobiMerged")
      gradientSubtract = try load("fluidGradientSubtract")
      blurH = try load("fluidBlurH")
      blurV = try load("fluidBlurV")
      bloomThresholdBlurH = try load("fluidBloomThresholdBlurH")
      bloomDownsample = try load("fluidBloomDownsample")
      render = try load("fluidRender")
      clearRGBA = try load("fluidClearRGBA")
      buoyancy = try load("fluidBuoyancy")
      vortexField = try load("fluidVortexField")
      dyeMapReset = try load("fluidDyeMapReset")
      dyeMapAccumulate = try load("fluidDyeMapAccumulate")
      dyeMapAdvance = try load("fluidDyeMapAdvance")
      dyeMapLookup = try load("fluidDyeMapLookup")
      dyeMapError = try load("fluidDyeMapError")
      dyeMapCorrect = try load("fluidDyeMapCorrect")
      dyeDiffuse = try load("fluidDyeDiffuse")
      divergenceRHS = try load("fluidDivergenceRHS")
      mgDescendDivergence = try load("fluidMGDescendDivergence")
      mgDescendZero = try load("fluidMGDescendZero")
      mgDescend = try load("fluidMGDescend")
      mgAscend = try load("fluidMGAscend")
      mgAscendProject = try load("fluidMGAscendProject")
      mgCoarseSolve = try load("fluidMGCoarseSolve")
      resample = try load("fluidResample")
      technicolorBakeLUT = try load("technicolorBakeLUT")
    }
  }

  struct Textures {
    let velocityA: MTLTexture
    let velocityB: MTLTexture
    let pressure: MTLTexture
    let divergence: MTLTexture
    let dyeA: MTLTexture
    let dyeB: MTLTexture
    let dyeC: MTLTexture
    let dye0: MTLTexture
    let dyePsiA: MTLTexture
    let dyePsiB: MTLTexture
    let dyePhiA: MTLTexture
    let dyePhiB: MTLTexture
    let bloomA: MTLTexture
    let bloomB: MTLTexture
    let bloomMidA: MTLTexture
    let bloomLoA: MTLTexture
    let psiA: MTLTexture
    let psiB: MTLTexture
    let u0: MTLTexture
    let dyeVelocityA: MTLTexture
    let dyeVelocityB: MTLTexture
    let vortexFlowA: MTLTexture
    let vortexFlowB: MTLTexture
    let vortexField: MTLTexture
    let cloudBillowA: MTLTexture
    let cloudBillowB: MTLTexture
    let cloudDensity: [MTLTexture]
    let cloudLight: MTLTexture
    let mgPressure: [MTLTexture]
    let mgCorrected: [MTLTexture]
    let mgRHS: [MTLTexture]

    init(width: Int, height: Int, levels: MultigridLevels,
         make: (MTLPixelFormat, String, Int, Int) -> MTLTexture?) throws(MissingResource) {
      func load(_ format: MTLPixelFormat, _ label: String,
                _ w: Int = width, _ h: Int = height) throws(MissingResource) -> MTLTexture {
        guard let texture = make(format, label, w, h) else { throw MissingResource(name: label) }
        return texture
      }

      let dyeMapWidth = max(width / dyeMapDivisor, 1), dyeMapHeight = max(height / dyeMapDivisor, 1)

      velocityA = try load(.rg16Float, "velocityA")
      velocityB = try load(.rg16Float, "velocityB")
      pressure = try load(.r16Float, "pressure")
      divergence = try load(.r16Float, "divergence")
      dyeA = try load(.rgba16Float, "dyeA")
      dyeB = try load(.rgba16Float, "dyeB")
      dyeC = try load(.rgba16Float, "dyeC")
      dye0 = try load(.rgba16Float, "dye0")
      dyePsiA = try load(.rg32Float, "dyePsiA", dyeMapWidth, dyeMapHeight)
      dyePsiB = try load(.rg32Float, "dyePsiB", dyeMapWidth, dyeMapHeight)
      dyePhiA = try load(.rg32Float, "dyePhiA", dyeMapWidth, dyeMapHeight)
      dyePhiB = try load(.rg32Float, "dyePhiB", dyeMapWidth, dyeMapHeight)
      bloomA = try load(.rgba16Float, "bloomA", bloomSize, bloomSize)
      bloomB = try load(.rgba16Float, "bloomB", bloomSize, bloomSize)
      bloomMidA = try load(.rgba16Float, "bloomMidA", bloomSizeMid, bloomSizeMid)
      bloomLoA = try load(.rgba16Float, "bloomLoA", bloomSizeLo, bloomSizeLo)
      psiA = try load(.rg32Float, "psiA")
      psiB = try load(.rg32Float, "psiB")
      u0 = try load(.rg16Float, "u0")
      dyeVelocityA = try load(.rg16Float, "dyeVelocityA", width / 4, height / 4)
      dyeVelocityB = try load(.rg16Float, "dyeVelocityB", width / 4, height / 4)
      vortexFlowA = try load(.rg16Float, "vortexFlowA", max(width / 8, 1), max(height / 8, 1))
      vortexFlowB = try load(.rg16Float, "vortexFlowB", max(width / 16, 1), max(height / 16, 1))
      vortexField = try load(.rgba16Float, "vortexField", max(width / 16, 1), max(height / 16, 1))
      cloudBillowA = try load(.r16Float, "cloudBillowA", width / 4, height / 4)
      cloudBillowB = try load(.r16Float, "cloudBillowB", width / 4, height / 4)
      cloudLight = try load(.r16Float, "cloudLight", width / 4, height / 4)

      var cloudDensity = [MTLTexture]()
      for level in 0..<cloudLevels {
        let w = max(width / (4 << level), 1), h = max(height / (4 << level), 1)
        cloudDensity.append(try load(.r16Float, "cloudDensity\(level)", w, h))
      }
      self.cloudDensity = cloudDensity

      mgPressure = levels.pressure
      mgCorrected = levels.corrected
      mgRHS = levels.rhs
    }
  }

  nonisolated static func createPipelines(device: MTLDevice, compiler: any MTL4Compiler) -> Pipelines? {
    guard let library = device.makeDefaultLibrary() else {
      logger.error("Failed to create default Metal library")
      return nil
    }
    return try? Pipelines { name in Self.makePipeline(name, library: library, compiler: compiler) }
  }

  static func createArgumentTables(device: MTLDevice) -> [any MTL4ArgumentTable]? {
    let desc = MTL4ArgumentTableDescriptor()
    desc.maxTextureBindCount = 8
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

  static let technicolorLUTSize: Int = 33
  static let outputExtendedRange = true
  static let standardRangePixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
  static let standardRangeColorSpace = CGColorSpace(name: CGColorSpace.displayP3)
  static let outputPixelFormat: MTLPixelFormat = outputExtendedRange ? .rgba16Float : standardRangePixelFormat
  static let outputColorSpace = outputExtendedRange
    ? CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) : standardRangeColorSpace

  static func createTechnicolorLUT(device: MTLDevice) -> MTLTexture? {
    let desc = MTLTextureDescriptor()
    desc.textureType = .type3D
    desc.pixelFormat = .rgba16Float
    desc.width = technicolorLUTSize
    desc.height = technicolorLUTSize
    desc.depth = technicolorLUTSize
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private
    let texture = device.makeTexture(descriptor: desc)
    texture?.label = "Technicolor IV print LUT"
    return texture
  }

  static let bloomSize: Int = 256
  static let bloomSizeMid: Int = 128
  static let bloomSizeLo: Int = 64
  static let cloudLevels: Int = 6

  static func createTextures(device: MTLDevice, width: Int, height: Int) -> Textures? {
    guard let levels = createMultigridLevels(device: device, width: width, height: height) else {
      return nil
    }

    return try? Textures(width: width, height: height, levels: levels) { format, label, w, h in
      let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: format, width: w, height: h, mipmapped: false
      )
      desc.usage = [.shaderRead, .shaderWrite]
      desc.storageMode = .private
      guard let texture = device.makeTexture(descriptor: desc) else {
        logger.error("Failed to create texture '\(label)'")
        return nil
      }
      texture.label = label
      return texture
    }
  }

  struct MultigridLevels {
    var pressure = [MTLTexture]()
    var corrected = [MTLTexture]()
    var rhs = [MTLTexture]()
  }

  static func createMultigridLevels(device: MTLDevice,
                                    width: Int,
                                    height: Int) -> MultigridLevels? {
    var levels = MultigridLevels()
    var w = width
    var h = height
    while true {
      let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .r32Float, width: w, height: h, mipmapped: false
      )
      desc.usage = [.shaderRead, .shaderWrite]
      desc.storageMode = .private
      guard let pressure = device.makeTexture(descriptor: desc),
            let corrected = device.makeTexture(descriptor: desc),
            let rhs = device.makeTexture(descriptor: desc) else {
        logger.error("Failed to create multigrid level \(w)x\(h)")
        return nil
      }
      pressure.label = "mgPressure\(w)x\(h)"
      corrected.label = "mgCorrected\(w)x\(h)"
      rhs.label = "mgRHS\(w)x\(h)"
      levels.pressure.append(pressure)
      levels.corrected.append(corrected)
      levels.rhs.append(rhs)
      if w * h <= multigridCoarseCells || (w <= 2 && h <= 2) { break }
      w = (w + 1) / 2
      h = (h + 1) / 2
    }
    return levels
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

    encoder.setComputePipelineState(pipelines.technicolorBakeLUT)
    argumentTable.setTexture(technicolorLUT.gpuResourceID, index: 0)
    let densityAndSharpen = SIMD2<Float>(Self.renderTechnicolorPrintDensity, Self.renderTechnicolorSharpen)
    argumentTable.setAddress(writeUniform(densityAndSharpen), index: 0)
    encoder.dispatchThreads(
      threadsPerGrid: MTLSize(width: Self.technicolorLUTSize, height: Self.technicolorLUTSize,
                              depth: Self.technicolorLUTSize),
      threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 4))

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
      pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
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
    residencySet.addAllocation(technicolorLUT)
    residencySet.addAllocation(stretchStatsBuffer)
    for buf in uniformBuffers { residencySet.addAllocation(buf) }

    residencySet.commit()

    commandQueue.addResidencySet(residencySet)
  }
}

#endif
