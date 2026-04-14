//
//  GameOfLifeRenderer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/12/26.
//

import Metal
import os
import QuartzCore

struct GameOfLifeParams {
  var bass: Float
  var mid: Float
  var high: Float
  var time: Float
  var simWidth: UInt32
  var simHeight: UInt32
  var frameCount: UInt32
  var spawnRate: Float
}

nonisolated let gameOfLifeLogger = Logger(subsystem: "com.VisualMan", category: "GameOfLifeRenderer")

@MainActor
final class GameOfLifeRenderer: MetalVisualizerRenderer {
  let device: MTLDevice
  let commandQueue: any MTL4CommandQueue

  var stepPipeline: MTLComputePipelineState
  var renderPipeline: MTLComputePipelineState

  static let longAxisCells: Int = 87
  static let minShortAxisCells: Int = 20
  var simWidth: Int = 0
  var simHeight: Int = 0

  var simA: MTLTexture?
  var simB: MTLTexture?

  var displayIntermediate: MTLTexture?
  var lastDrawableWidth: Int = 0
  var lastDrawableHeight: Int = 0
  var pendingTextureReleases: [(frame: UInt64, texture: MTLTexture)] = []

  var time: Float = 0
  var dt: Float = 1.0 / 60.0
  var renderFrameCount: UInt32 = 0

  var smoothedBass: Float = 0
  var smoothedMid: Float = 0
  var needsAudioReseed: Bool = true

  static let baseStepInterval: Int = 10
  static let rampStepFrames: UInt32 = 30
  var stepAccumulator: Int = 0
  var simFrameCount: UInt32 = 0

  static let maxFramesInFlight: UInt64 = 3
  var commandAllocators = [any MTL4CommandAllocator]()
  var commandBuffer: any MTL4CommandBuffer
  var argumentTable: any MTL4ArgumentTable
  var uniformBuffers = [MTLBuffer]()
  var uniformOffset: Int = 0
  static let uniformBufferSize: Int = 4096
  let sharedEvent: MTLSharedEvent
  var frameNumber: UInt64 = 0
  let residencySet: MTLResidencySet

  var currentUniformBuffer: MTLBuffer

  private static var logger: Logger { gameOfLifeLogger }

  static func create() async -> GameOfLifeRenderer? {
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
    guard let renderer = GameOfLifeRenderer(device: device, pipelines: pipelines) else { return nil }
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

    var allocators = [any MTL4CommandAllocator]()
    var buffers = [MTLBuffer]()
    for _ in 0..<Self.maxFramesInFlight {
      guard let allocator = device.makeCommandAllocator(),
            let buffer = device.makeBuffer(length: Self.uniformBufferSize, options: .storageModeShared) else {
        return nil
      }
      allocators.append(allocator)
      buffers.append(buffer)
    }
    guard let firstBuffer = buffers.first else { return nil }

    let tableDesc = MTL4ArgumentTableDescriptor()
    tableDesc.maxTextureBindCount = 2
    tableDesc.maxBufferBindCount = 1
    guard let argumentTable = try? device.makeArgumentTable(descriptor: tableDesc) else {
      return nil
    }

    let setDesc = MTLResidencySetDescriptor()
    setDesc.initialCapacity = 8
    guard let residencySet = try? device.makeResidencySet(descriptor: setDesc) else {
      return nil
    }

    self.device = device
    self.commandQueue = commandQueue
    self.commandBuffer = commandBuffer
    self.sharedEvent = sharedEvent
    self.commandAllocators = allocators
    self.uniformBuffers = buffers
    self.currentUniformBuffer = firstBuffer
    self.argumentTable = argumentTable
    self.stepPipeline = pipelines.step
    self.renderPipeline = pipelines.render
    self.residencySet = residencySet

    for buf in uniformBuffers { residencySet.addAllocation(buf) }
    residencySet.commit()
    commandQueue.addResidencySet(residencySet)
  }

  func warmUpGPU() {
    guard let textures = makeWarmUpTextures() else { return }

    residencySet.addAllocation(textures.simA)
    residencySet.addAllocation(textures.simB)
    residencySet.addAllocation(textures.display)
    residencySet.commit()
    defer {
      residencySet.removeAllocation(textures.simA)
      residencySet.removeAllocation(textures.simB)
      residencySet.removeAllocation(textures.display)
      residencySet.commit()
    }

    let allocator = commandAllocators[0]
    currentUniformBuffer = uniformBuffers[0]
    allocator.reset()
    uniformOffset = 0

    commandBuffer.beginCommandBuffer(allocator: allocator)
    commandBuffer.useResidencySet(residencySet)
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setArgumentTable(argumentTable)

    encodeWarmUpPasses(encoder: encoder, textures: textures)

    encoder.endEncoding()
    commandBuffer.endCommandBuffer()
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: 1)
    frameNumber = 1
  }

  func canRenderThisFrame() -> Bool {
    let nextFrame = frameNumber + 1
    if nextFrame > Self.maxFramesInFlight {
      let waitValue = nextFrame - Self.maxFramesInFlight
      return sharedEvent.signaledValue >= waitValue
    }
    return true
  }

  func ensureSimTextures(drawableWidth: Int, drawableHeight: Int) {
    guard simA == nil || simB == nil else { return }

    let longScreen = max(drawableWidth, drawableHeight)
    let shortScreen = min(drawableWidth, drawableHeight)
    let aspect = Float(shortScreen) / Float(longScreen)
    let shortAxis = max(Self.minShortAxisCells,
                        Int((Float(Self.longAxisCells) * aspect).rounded()))

    simWidth = shortAxis
    simHeight = Self.longAxisCells

    guard let textures = Self.createSimTextures(device: device, width: simWidth, height: simHeight) else {
      Self.logger.error("Failed to create adaptive sim textures")
      return
    }
    simA = textures.a
    simB = textures.b
    residencySet.addAllocation(textures.a)
    residencySet.addAllocation(textures.b)
    residencySet.commit()

    seedInitialState()
  }

  func drainPendingTextureReleases() {
    guard !pendingTextureReleases.isEmpty else { return }
    let signaled = sharedEvent.signaledValue
    var removedAny = false
    pendingTextureReleases.removeAll { entry in
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

  func ensureDisplayIntermediate(width: Int, height: Int) -> Bool {
    if width == lastDrawableWidth
        && height == lastDrawableHeight
        && displayIntermediate != nil {
      return true
    }

    if let old = displayIntermediate {
      pendingTextureReleases.append((frame: frameNumber, texture: old))
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
      lastDrawableWidth = 0
      lastDrawableHeight = 0
      return false
    }

    residencySet.addAllocation(tex)
    residencySet.commit()

    displayIntermediate = tex
    lastDrawableWidth = width
    lastDrawableHeight = height
    return true
  }

  struct Pipelines {
    let step: MTLComputePipelineState
    let render: MTLComputePipelineState
  }

  func writeUniform<T>(_ value: T) -> MTLGPUAddress {
    let aligned = (uniformOffset + 15) & ~15
    let end = aligned + MemoryLayout<T>.size
    guard end <= Self.uniformBufferSize else {
      Self.logger.error("Uniform buffer overflow")
      return currentUniformBuffer.gpuAddress
    }
    (currentUniformBuffer.contents() + aligned).storeBytes(of: value, as: T.self)
    let addr = currentUniformBuffer.gpuAddress + MTLGPUAddress(aligned)
    uniformOffset = end
    return addr
  }

}
