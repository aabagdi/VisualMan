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
  var bloomMidB: MTLTexture
  var bloomLoA: MTLTexture
  var bloomLoB: MTLTexture
  var psiA: MTLTexture
  var psiB: MTLTexture
  var u0: MTLTexture
  
  var time: Float = 0
  var dt: Float = 1.0 / 60.0
  private var lastFrameTime: CFTimeInterval = 0
  private var smoothedBass: Float = 0
  private var smoothedMid: Float = 0
  var prevBass: Float = 0
  var prevMid: Float = 0

  private var resumeSuppressionRemaining: Float = 0
  private let velocityDissipation: Float = 0.985
  private let dyeDissipation: Float = 0.98
  private let maxJacobiIterations: Int = 16
  private let rampUpFrames: UInt64 = 180
  var renderFrameCount: UInt64 = 0
  
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
    self.bloomMidB = textures.bloomMidB
    self.bloomLoA = textures.bloomLoA
    self.bloomLoB = textures.bloomLoB
    self.psiA = textures.psiA
    self.psiB = textures.psiB
    self.u0 = textures.u0
    self.residencySet = residencySet

    configureResidencySet()
  }
  
  func writeUniform<T>(_ value: T) -> MTLGPUAddress {
    let aligned = (uniformOffset + 15) & ~15
    let end = aligned + MemoryLayout<T>.size
    guard end <= Self.uniformBufferSize else {
      Self.logger.error("Uniform buffer overflow: need \(end) bytes, have \(Self.uniformBufferSize)")
      return currentUniformBuffer.gpuAddress
    }
    (currentUniformBuffer.contents() + aligned).storeBytes(of: value, as: T.self)
    let addr = currentUniformBuffer.gpuAddress + MTLGPUAddress(aligned)
    uniformOffset = end
    return addr
  }

  func writeUniformArray<T>(_ values: [T]) -> MTLGPUAddress {
    let aligned = (uniformOffset + 15) & ~15
    let size = MemoryLayout<T>.stride * values.count
    let end = aligned + size
    guard end <= Self.uniformBufferSize else {
      Self.logger.error("Uniform array buffer overflow: need \(end) bytes, have \(Self.uniformBufferSize)")
      return currentUniformBuffer.gpuAddress
    }
    let ptr = currentUniformBuffer.contents() + aligned
    values.withUnsafeBufferPointer { buf in
      if let baseAddress = buf.baseAddress {
        memcpy(ptr, baseAddress, size)
      }
    }
    let addr = currentUniformBuffer.gpuAddress + MTLGPUAddress(aligned)
    uniformOffset = end
    return addr
  }
  
  func prepareForResume() {
    lastFrameTime = 0
    resumeSuppressionRemaining = 0.5
  }

  func update(bass: Float,
              mid: Float,
              high: Float,
              drawable: CAMetalDrawable) {
    let drawableTexture = drawable.texture

    let nextFrame = frameNumber + 1
    let frameIndex = Int(nextFrame % Self.maxFramesInFlight)

    if nextFrame > Self.maxFramesInFlight {
      let waitValue = nextFrame - Self.maxFramesInFlight
      guard sharedEvent.signaledValue >= waitValue else { return }
    }

    frameNumber = nextFrame

    let allocator = commandAllocators[frameIndex]
    currentUniformBuffer = uniformBuffers[frameIndex]
    allocator.reset()
    uniformOffset = 0
    
    renderFrameCount += 1

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

    commandBuffer.beginCommandBuffer(allocator: allocator)
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setArgumentTable(argumentTable)

    ensureTAAHistory(width: drawableTexture.width, height: drawableTexture.height)

    runSimulationPass(encoder: encoder, bass: bass, mid: mid, high: high,
                      output: drawableTexture)

    if taaHistoryA != nil && taaHistoryB != nil {
      taaHistoryValid = true
    }
    
    encoder.endEncoding()
    commandBuffer.endCommandBuffer()
    
    commandQueue.waitForDrawable(drawable)
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: frameNumber)
    commandQueue.signalDrawable(drawable)
    drawable.present()
  }

}

private extension NavierStokesRenderer {
  var currentJacobiIterations: Int {
    let t = min(Float(renderFrameCount) / Float(rampUpFrames), 1.0)
    return max(Int(Float(maxJacobiIterations) * t), 4)
  }

  func runSimulationPass(encoder: any MTL4ComputeCommandEncoder,
                         bass: Float, mid: Float, high: Float,
                         output: MTLTexture) {
    let validFlag: UInt32 = taaHistoryValid ? 1 : 0
    let frameUniforms = FrameUniforms(
      bass: bass, mid: mid, high: high,
      time: time, dt: dt,
      taaBlend: taaBlendFactor,
      historyValid: validFlag
    )
    frameUniformsAddress = writeUniform(frameUniforms)

    let suppress = resumeSuppressionRemaining > 0
    let injBass  = suppress ? 0 : bass
    let injMid   = suppress ? 0 : mid
    let injHigh  = suppress ? 0 : high

    advectPsi(encoder: encoder)
    swap(&psiA, &psiB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    covectorPullback(encoder: encoder, dissipation: 0.995)
    swap(&velocityA, &velocityB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    injectAudioSplats(encoder: encoder, bass: injBass, mid: injMid, high: injHigh)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    applyVorticityConfinement(encoder: encoder, bass: injBass, mid: injMid)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    project(encoder: encoder, jacobiIterations: currentJacobiIterations)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    framesSinceReinit += 1
    if framesSinceReinit >= reinitInterval {
      reinitFlowMap(encoder: encoder)
      framesSinceReinit = 0
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }

    let dynamicDyeDissipation: Float = 0.98 + bass * 0.01 + mid * 0.008
    advectDyeMacCormack(encoder: encoder, dissipation: dynamicDyeDissipation)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    runBloomPasses(encoder: encoder)

    render(encoder: encoder, output: output, bass: bass, mid: mid)
  }

  func runBloomPasses(encoder: any MTL4ComputeCommandEncoder) {
    bloomThresholdBlurH(encoder: encoder, dst: bloomB, size: Self.bloomSize)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    blurBloomV(encoder: encoder, src: bloomB, dst: bloomA, size: Self.bloomSize)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    bloomThresholdBlurH(encoder: encoder, dst: bloomMidB, size: Self.bloomSizeMid)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    blurBloomV(encoder: encoder, src: bloomMidB, dst: bloomMidA, size: Self.bloomSizeMid)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    bloomThresholdBlurH(encoder: encoder, dst: bloomLoB, size: Self.bloomSizeLo)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    blurBloomV(encoder: encoder, src: bloomLoB, dst: bloomLoA, size: Self.bloomSizeLo)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
  }
}
