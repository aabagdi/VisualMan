//
//  NavierStokesRenderer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import Metal
import os
import QuartzCore

struct SplatParams {
  var position: SIMD2<Float>
  var radius: Float
  var padding: Float = 0
  var value: SIMD3<Float>
  var padding2: Float = 0

  init(position: SIMD2<Float>, value: SIMD3<Float>, radius: Float) {
    self.position = position
    self.value = value
    self.radius = radius
  }
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
}

@MainActor
final class NavierStokesRenderer: MetalVisualizerRenderer {
  let device: MTLDevice
  let commandQueue: any MTL4CommandQueue
  
  nonisolated static let logger = Logger(subsystem: "com.VisualMan", category: "NavierStokesRenderer")
  static let gridSize: Int = 1024
  var gridSize: Int { Self.gridSize }
  
  let pipelines: Pipelines
  
  var velocityA: MTLTexture
  var velocityB: MTLTexture
  var pressure: MTLTexture
  var divergenceTexture: MTLTexture
  var dyeA: MTLTexture
  var dyeB: MTLTexture
  var dyeC: MTLTexture
  var bloomA: MTLTexture
  var bloomB: MTLTexture
  var bloomMidA: MTLTexture
  var bloomLoA: MTLTexture
  var psiA: MTLTexture
  var psiB: MTLTexture
  var psiC: MTLTexture
  var u0: MTLTexture

  var displayIntermediate: MTLTexture?
  private var lastDisplayWidth: Int = 0
  private var lastDisplayHeight: Int = 0
  private var pendingDisplayReleases: [(frame: UInt64, texture: MTLTexture)] = []

  var time: Float = 0
  var dt: Float = 1.0 / 60.0
  private var lastFrameTime: CFTimeInterval = 0
  private var smoothedBass: Float = 0
  private var smoothedMid: Float = 0
  var prevBass: Float = 0
  var prevMid: Float = 0

  var resumeSuppressionRemaining: Float = 0
  private let velocityDissipation: Float = 0.985
  private let dyeDissipation: Float = 0.98
  let jacobiIterations: Int = 16

  static let maxFramesInFlight: UInt64 = 3
  var commandAllocators = [any MTL4CommandAllocator]()
  var commandBuffer: any MTL4CommandBuffer
  var argumentTable: any MTL4ArgumentTable
  var uniformBuffers = [MTLBuffer]()
  var uniformOffset: Int = 0
  static let uniformBufferSize: Int = 16384
  let sharedEvent: MTLSharedEvent
  var frameNumber: UInt64 = 0
  let residencySet: MTLResidencySet
  let reinitInterval: Int = 6

  var taaHistoryA: MTLTexture?
  var taaHistoryB: MTLTexture?
  var taaHistoryValid: Bool = false
  var taaHistoryWidth: Int = 0
  var taaHistoryHeight: Int = 0
  let taaBlendFactor: Float = 0.85
  var pendingTAAHistoryReleases = [(frame: UInt64, texture: MTLTexture)]()

  var frameUniformsAddress: MTLGPUAddress = 0
  var framesSinceReinit: Int = 6
  
  var currentUniformBuffer: MTLBuffer
  
  static func create() async -> NavierStokesRenderer? {
    let prepared = await Task.detached(priority: .userInitiated) {
      guard let device = MTLCreateSystemDefaultDevice(),
            let compiler = try? device.makeCompiler(descriptor: MTL4CompilerDescriptor()) else {
        return nil as (MTLDevice, Pipelines)?
      }
      guard let pipelines = createPipelines(device: device, compiler: compiler) else {
        return nil
      }
      return (device, pipelines)
    }.value

    guard let (device, pipelines) = prepared else { return nil }
    guard let renderer = NavierStokesRenderer(device: device, pipelines: pipelines) else { return nil }
    renderer.warmUpGPU()
    return renderer
  }

  private init?(device: MTLDevice, pipelines: Pipelines) {
    guard let commandQueue = device.makeMTL4CommandQueue(),
          let commandBuffer = device.makeCommandBuffer(),
          let sharedEvent = device.makeSharedEvent() else {
      return nil
    }
    sharedEvent.signaledValue = 0

    guard let allocatorsAndBuffers = Self.createAllocatorsAndBuffers(device: device),
          let firstUniformBuffer = allocatorsAndBuffers.buffers.first else { return nil }

    guard let argumentTable = Self.createArgumentTable(device: device) else { return nil }
    guard let textures = Self.createTextures(device: device) else { return nil }
    guard let residencySet = Self.createResidencySet(device: device) else { return nil }

    self.device = device
    self.commandQueue = commandQueue
    self.commandBuffer = commandBuffer
    self.sharedEvent = sharedEvent
    self.commandAllocators = allocatorsAndBuffers.allocators
    self.uniformBuffers = allocatorsAndBuffers.buffers
    self.currentUniformBuffer = firstUniformBuffer
    self.argumentTable = argumentTable
    self.pipelines = pipelines
    self.velocityA = textures.velocityA
    self.velocityB = textures.velocityB
    self.pressure = textures.pressure
    self.divergenceTexture = textures.divergence
    self.dyeA = textures.dyeA
    self.dyeB = textures.dyeB
    self.dyeC = textures.dyeC
    self.bloomA = textures.bloomA
    self.bloomB = textures.bloomB
    self.bloomMidA = textures.bloomMidA
    self.bloomLoA = textures.bloomLoA
    self.psiA = textures.psiA
    self.psiB = textures.psiB
    self.psiC = textures.psiC
    self.u0 = textures.u0
    self.residencySet = residencySet

    configureResidencySet()
  }

  func prepareForResume() {
    lastFrameTime = 0
    resumeSuppressionRemaining = 0.5
  }

  private func drainPendingDisplayReleases() {
    guard !pendingDisplayReleases.isEmpty else { return }
    let signaled = sharedEvent.signaledValue
    var removedAny = false
    pendingDisplayReleases.removeAll { entry in
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

  private func ensureDisplayIntermediate(width: Int, height: Int) -> Bool {
    if width == lastDisplayWidth
        && height == lastDisplayHeight
        && displayIntermediate != nil {
      return true
    }

    if let old = displayIntermediate {
      pendingDisplayReleases.append((frame: frameNumber, texture: old))
    }

    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private

    guard let tex = device.makeTexture(descriptor: desc) else {
      displayIntermediate = nil
      lastDisplayWidth = 0
      lastDisplayHeight = 0
      return false
    }

    residencySet.addAllocation(tex)
    residencySet.commit()

    displayIntermediate = tex
    lastDisplayWidth = width
    lastDisplayHeight = height
    return true
  }

  func encodeFrame(bass: Float,
                   mid: Float,
                   high: Float,
                   drawableWidth: Int,
                   drawableHeight: Int) -> MTLTexture? {
    drainPendingDisplayReleases()

    guard ensureDisplayIntermediate(width: drawableWidth,
                                    height: drawableHeight),
          let displayTex = displayIntermediate else {
      return nil
    }

    let now = CACurrentMediaTime()
    if lastFrameTime == 0 {
      dt = 0
    } else {
      dt = Float(max(1.0 / 240.0, min(1.0 / 30.0, now - lastFrameTime)))
    }
    lastFrameTime = now

    let bassTau: Float = bass > smoothedBass ? 0.04 : 0.15
    let midTau: Float = mid  > smoothedMid  ? 0.05 : 0.18
    smoothedBass += (bass - smoothedBass) * (1 - exp(-dt / bassTau))
    smoothedMid  += (mid  - smoothedMid)  * (1 - exp(-dt / midTau))

    resumeSuppressionRemaining = max(0, resumeSuppressionRemaining - dt)

    time += dt * (1.0 + smoothedBass * 0.5 + smoothedMid * 0.3)

    guard let encoder = beginFrame() else { return nil }

    ensureTAAHistory(width: displayTex.width, height: displayTex.height)

    runSimulationPass(encoder: encoder, bass: bass, mid: mid, high: high,
                      output: displayTex)

    if taaHistoryA != nil && taaHistoryB != nil {
      taaHistoryValid = true
    }

    encoder.endEncoding()

    return displayTex
  }
}
