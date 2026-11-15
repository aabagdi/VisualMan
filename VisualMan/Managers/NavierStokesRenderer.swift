//
//  NavierStokesRenderer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

enum NavierStokesSolver: String, CaseIterable {
  case pressureMultigrid = "V-grid solver (more realistic)"
  case jacobi = "Jacobi solver (more efficient)"
}

#if !targetEnvironment(simulator)
import Metal
import os
import QuartzCore

struct SplatParams {
  var position: SIMD2<Float>
  var radius: Float
  var padding: Float = 0
  var value: SIMD3<Float>
  var weight: Float = 0
  var clumpOffset: SIMD2<Float> = .zero
  var clumpValue: SIMD3<Float> = .zero

  init(position: SIMD2<Float>, value: SIMD3<Float>, radius: Float, weight: Float = 0,
       clumpOffset: SIMD2<Float> = .zero, clumpValue: SIMD3<Float> = .zero) {
    self.position = position
    self.value = value
    self.radius = radius
    self.weight = weight
    self.clumpOffset = clumpOffset
    self.clumpValue = clumpValue
  }
}

struct SplatBatchParams {
  var velocityMode: UInt32
  var clumping: Float
  var clumpScale: Float
  var clumpHue: Float
}

struct FrameUniforms {
  var bass: Float
  var mid: Float
  var high: Float
  var time: Float
  var dt: Float
  var taaBlend: Float
  var historyValid: UInt32
  var _pad: UInt32 = 0
  var shading: Float
  var detail: Float
  var jitter: Float
  var thinFade: Float
  var technicolorPresence: Float
  var technicolorNeutralReach: Float
  var technicolorLampGain: Float
  var technicolorCeiling: Float
  var technicolorTheme: SIMD4<Float>
  var technicolorMisregistration: SIMD4<Float>
  var technicolorDepth: SIMD4<Float>
}

struct CloudUniforms {
  var advectStep: Float
  var regrow: Float
  var time: Float
  var billow: Float
  var billowScale: Float
  var shadow: Float
  var relief: Float
  var cavity: Float
  var ambient: Float
  var sun: Float
  var thickness: Float
  var vortexLift: Float
  var vortexPresence: Float
}

struct DyeMapUniforms {
  var gridSize: SIMD2<Float>
  var traceLimits: SIMD2<Float>
  var dt: Float
  var strayCells: Float
}

struct VortexUniforms {
  var cells: Float
  var floor: Float
  var cap: Float
  var swirlScale: Float
}

@MainActor
final class NavierStokesRenderer: MetalVisualizerRenderer {
  let device: MTLDevice
  let commandQueue: any MTL4CommandQueue
  
  nonisolated static let logger = Logger(subsystem: "com.VisualMan", category: "NavierStokesRenderer")

  static let simulationCellBudget: Int = 1024 * 1024
  static let gridAlignment: Int = 32
  static let minGridDimension: Int = 128
  static let maxGridDimension: Int = 2048
  var gridWidth: Int
  var gridHeight: Int
  var gridAspect: Float = 1
  var gridScale: Float { sqrt(Float(gridWidth * gridHeight)) }

  let pipelines: Pipelines

  var solver: NavierStokesSolver = .pressureMultigrid
  
  var velocityA: MTLTexture
  var velocityB: MTLTexture
  var pressure: MTLTexture
  var divergenceTexture: MTLTexture
  var dyeA: MTLTexture
  var dyeB: MTLTexture
  var dyeC: MTLTexture
  var dye0: MTLTexture
  var dyePsiA: MTLTexture
  var dyePsiB: MTLTexture
  var dyePhiA: MTLTexture
  var dyePhiB: MTLTexture
  var bloomA: MTLTexture
  var bloomB: MTLTexture
  var bloomMidA: MTLTexture
  var bloomLoA: MTLTexture
  var psiA: MTLTexture
  var psiB: MTLTexture
  var u0: MTLTexture
  var dyeVelocityA: MTLTexture
  var dyeVelocityB: MTLTexture
  var vortexFlowA: MTLTexture
  var vortexFlowB: MTLTexture
  var vortexField: MTLTexture
  var cloudBillowA: MTLTexture
  var cloudBillowB: MTLTexture
  var cloudDensity: [MTLTexture]
  var cloudLight: MTLTexture

  var mgPressure: [MTLTexture]
  var mgCorrected: [MTLTexture]
  var mgRHS: [MTLTexture]

  let technicolorLUT: MTLTexture

  let stretchStatsBuffer: MTLBuffer
  static let stretchStatsStride: Int = 32
  var lastStretchedFraction: Float = 0
  var lastFastFraction: Float = 0
  var lastDyeStrayFraction: Float = 0
  var statsLogCountdown: Int = 0

  static let renderScale: Float = 0.75

  var time: Float = 0
  var dt: Float = 1.0 / 60.0
  private var lastFrameTime: CFTimeInterval = 0
  private var smoothedBass: Float = 0
  private var smoothedMid: Float = 0
  var bassEnvelope: Float = 0
  var midEnvelope: Float = 0
  var highEnvelope: Float = 0
  var bassFast: Float = 0
  var midFast: Float = 0
  var highFast: Float = 0
  var bassBurst: Float = 0
  var midBurst: Float = 0
  var highBurst: Float = 0
  var dynamicsWarm: Bool = false
  var lastExcitement: Float = 0
  var wobblePhase: Float = 0
  var jetTravel = [SIMD2<Float>](repeating: .zero, count: NavierStokesRenderer.jetCount)

  var resumeSuppressionRemaining: Float = 0
  let jacobiIterations: Int = 16

  static let maxFramesInFlight: UInt64 = 3
  var commandAllocators = [any MTL4CommandAllocator]()
  var commandBuffer: any MTL4CommandBuffer
  var argumentTables: [any MTL4ArgumentTable]
  var uniformBuffers = [MTLBuffer]()
  var uniformOffset: Int = 0
  static let uniformBufferSize: Int = 16384
  let sharedEvent: MTLSharedEvent
  var frameNumber: UInt64 = 0
  let residencySet: MTLResidencySet

  var taaHistoryA: MTLTexture?
  var taaHistoryB: MTLTexture?
  var taaHistoryValid: Bool = false
  var taaHistoryWidth: Int = 0
  var taaHistoryHeight: Int = 0
  let taaBlendFactor: Float = 0.85

  var displayHeadroom: Float = 1
  var technicolorCeiling: Float = 1
  var pendingTAAHistoryReleases = [(frame: UInt64, texture: MTLTexture)]()

  var frameUniformsAddress: MTLGPUAddress = 0
  var framesSinceReinit: Int = NavierStokesRenderer.reinitMaxInterval
  var stepSinceReinit: Float = 0
  var framesSinceDyeReinit: Int = NavierStokesRenderer.dyeMapMaxInterval

  var gpuTiming: GPUTiming?

  var forceSplats = [SplatParams]()
  var dyeSplats = [SplatParams]()
  
  var currentUniformBuffer: MTLBuffer
  
  static func create(device: MTLDevice) async -> NavierStokesRenderer? {
    guard let pipelines = await compilePipelines(device: device),
          let resources = makeResources(device: device) else { return nil }
    let renderer = NavierStokesRenderer(device: device, pipelines: pipelines, resources: resources)
    renderer.warmUpGPU()
    return renderer
  }

  @concurrent
  nonisolated private static func compilePipelines(device: MTLDevice) async -> Pipelines? {
    guard let compiler = try? device.makeCompiler(descriptor: MTL4CompilerDescriptor()) else {
      return nil
    }
    return createPipelines(device: device, compiler: compiler)
  }

  private init(device: MTLDevice, pipelines: Pipelines, resources: Resources) {
    let textures = resources.textures
    self.device = device
    self.commandQueue = resources.commandQueue
    self.commandBuffer = resources.commandBuffer
    self.sharedEvent = resources.sharedEvent
    self.commandAllocators = resources.allocators
    self.uniformBuffers = resources.uniformBuffers
    self.currentUniformBuffer = resources.firstUniformBuffer
    self.argumentTables = resources.argumentTables
    self.pipelines = pipelines
    self.gridWidth = resources.gridSize
    self.gridHeight = resources.gridSize
    self.velocityA = textures.velocityA
    self.velocityB = textures.velocityB
    self.pressure = textures.pressure
    self.divergenceTexture = textures.divergence
    self.dyeA = textures.dyeA
    self.dyeB = textures.dyeB
    self.dyeC = textures.dyeC
    self.dye0 = textures.dye0
    self.dyePsiA = textures.dyePsiA
    self.dyePsiB = textures.dyePsiB
    self.dyePhiA = textures.dyePhiA
    self.dyePhiB = textures.dyePhiB
    self.bloomA = textures.bloomA
    self.bloomB = textures.bloomB
    self.bloomMidA = textures.bloomMidA
    self.bloomLoA = textures.bloomLoA
    self.psiA = textures.psiA
    self.psiB = textures.psiB
    self.u0 = textures.u0
    self.dyeVelocityA = textures.dyeVelocityA
    self.dyeVelocityB = textures.dyeVelocityB
    self.vortexFlowA = textures.vortexFlowA
    self.vortexFlowB = textures.vortexFlowB
    self.vortexField = textures.vortexField
    self.cloudBillowA = textures.cloudBillowA
    self.cloudBillowB = textures.cloudBillowB
    self.cloudDensity = textures.cloudDensity
    self.cloudLight = textures.cloudLight
    self.mgPressure = textures.mgPressure
    self.mgCorrected = textures.mgCorrected
    self.mgRHS = textures.mgRHS
    self.technicolorLUT = resources.technicolorLUT
    self.stretchStatsBuffer = resources.stretchStatsBuffer
    self.residencySet = resources.residencySet
    self.gpuTiming = GPUTiming.makeIfRequested(device: device)

    configureResidencySet()
  }

  func prepareForResume() {
    lastFrameTime = 0
    resumeSuppressionRemaining = 0.5
  }

  func setDisplayHeadroom(_ headroom: Float) {
    displayHeadroom = headroom
  }

  func encodeFrame(bass: Float,
                   mid: Float,
                   high: Float,
                   drawableWidth: Int,
                   drawableHeight: Int) -> MTLTexture? {
    let outWidth = max(1, Int((Float(drawableWidth) * Self.renderScale).rounded()))
    let outHeight = max(1, Int((Float(drawableHeight) * Self.renderScale).rounded()))

    ensureSimulationGrid(drawableWidth: drawableWidth, drawableHeight: drawableHeight)

    ensureTAAHistory(width: outWidth, height: outHeight)
    guard taaHistoryA != nil, taaHistoryB != nil else { return nil }

    let now = CACurrentMediaTime()
    if lastFrameTime == 0 {
      dt = 0
    } else {
      let rawGap = now - lastFrameTime
      dt = Float(max(1.0 / 240.0, min(1.0 / 30.0, rawGap)))
      if rawGap > 0.1 {
        taaHistoryValid = false
      }
    }
    lastFrameTime = now

    let bassTau: Float = bass > smoothedBass ? 0.04 : 0.15
    let midTau: Float = mid  > smoothedMid  ? 0.05 : 0.18
    smoothedBass += (bass - smoothedBass) * (1 - exp(-dt / bassTau))
    smoothedMid  += (mid  - smoothedMid)  * (1 - exp(-dt / midTau))

    resumeSuppressionRemaining = max(0, resumeSuppressionRemaining - dt)

    let timeStep = dt * (1.0 + smoothedBass * 0.5 + smoothedMid * 0.3)
    time += timeStep
    wobblePhase += timeStep * (1.0 + Self.excitementWobbleGain * lastExcitement)

    guard let encoder = beginFrame(),
          let historyA = taaHistoryA,
          let historyB = taaHistoryB else { return nil }

    encoder.barrier(afterQueueStages: [.dispatch, .fragment], beforeStages: .dispatch)

    let writeB = (frameNumber & 1) == 0
    let historyIn = writeB ? historyA : historyB
    let historyOut = writeB ? historyB : historyA

    runSimulationPass(encoder: encoder, bass: bass, mid: mid, high: high,
                      historyIn: historyIn, historyOut: historyOut)

    taaHistoryValid = true

    encoder.barrier(afterStages: .dispatch, beforeQueueStages: .fragment)
    encoder.endEncoding()

    return historyOut
  }
}

#endif
