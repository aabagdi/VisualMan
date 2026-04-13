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

  var time: Float = 0
  var dt: Float = 1.0 / 60.0
  var renderFrameCount: UInt32 = 0

  var smoothedBass: Float = 0
  var smoothedMid: Float = 0

  static let baseStepInterval: Int = 10
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
    return GameOfLifeRenderer(device: device, pipelines: pipelines)
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

  private func ensureSimTextures(drawableWidth: Int, drawableHeight: Int) {
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

  func update(bass: Float, mid: Float, high: Float, drawable: CAMetalDrawable) {
    ensureSimTextures(drawableWidth: drawable.texture.width,
                      drawableHeight: drawable.texture.height)
    guard let localSimA = simA, let localSimB = simB else { return }

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
    time += dt

    let (shouldStep, params) = updateAudioAndParams(bass: bass, mid: mid, high: high)

    commandBuffer.beginCommandBuffer(allocator: allocator)
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setArgumentTable(argumentTable)

    if shouldStep {
      stepAccumulator = 0
      simFrameCount += 1
      encodeStep(encoder: encoder, simA: localSimA, simB: localSimB, params: params)
    }

    let simSource = shouldStep ? localSimB : localSimA
    encodeRender(encoder: encoder, simSource: simSource, outputTex: drawable.texture, params: params)

    encoder.endEncoding()
    commandBuffer.endCommandBuffer()

    commandQueue.waitForDrawable(drawable)
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: frameNumber)
    commandQueue.signalDrawable(drawable)
    drawable.present()

    if shouldStep {
      swap(&simA, &simB)
    }
  }

  private func updateAudioAndParams(bass: Float, mid: Float, high: Float) ->
  (shouldStep: Bool, params: GameOfLifeParams) {
    let bassTau: Float = bass > smoothedBass ? 0.04 : 0.15
    let midTau: Float = mid > smoothedMid ? 0.05 : 0.18
    smoothedBass += (bass - smoothedBass) * (1 - exp(-dt / bassTau))
    smoothedMid += (mid - smoothedMid) * (1 - exp(-dt / midTau))

    let stepInterval = max(3, Self.baseStepInterval - Int(smoothedBass * 6.0))
    stepAccumulator += 1
    let shouldStep = stepAccumulator >= stepInterval

    let spawnRate: Float = 0.0008 + smoothedBass * 0.006

    let params = GameOfLifeParams(
      bass: bass,
      mid: mid,
      high: high,
      time: time,
      simWidth: UInt32(simWidth),
      simHeight: UInt32(simHeight),
      frameCount: simFrameCount,
      spawnRate: spawnRate
    )
    return (shouldStep, params)
  }

  func reset() {
    time = 0
    renderFrameCount = 0
    simFrameCount = 0
    stepAccumulator = 0
    smoothedBass = 0
    smoothedMid = 0
    seedInitialState()
  }

  private func encodeStep(encoder: some MTL4ComputeCommandEncoder,
                          simA: MTLTexture,
                          simB: MTLTexture,
                          params: GameOfLifeParams) {
    encoder.setComputePipelineState(stepPipeline)
    argumentTable.setTexture(simA.gpuResourceID, index: 0)
    argumentTable.setTexture(simB.gpuResourceID, index: 1)
    argumentTable.setAddress(writeUniform(params), index: 0)

    let simTG = MTLSize(width: 16, height: 16, depth: 1)
    let simGroups = MTLSize(
      width: (simWidth + 15) / 16,
      height: (simHeight + 15) / 16,
      depth: 1
    )
    encoder.dispatchThreadgroups(threadgroupsPerGrid: simGroups, threadsPerThreadgroup: simTG)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
  }

  private func encodeRender(encoder: some MTL4ComputeCommandEncoder,
                            simSource: MTLTexture,
                            outputTex: MTLTexture,
                            params: GameOfLifeParams) {
    encoder.setComputePipelineState(renderPipeline)
    argumentTable.setTexture(simSource.gpuResourceID, index: 0)
    argumentTable.setTexture(outputTex.gpuResourceID, index: 1)
    argumentTable.setAddress(writeUniform(params), index: 0)

    let renderTG = MTLSize(width: 16, height: 16, depth: 1)
    let renderGroups = MTLSize(
      width: (outputTex.width + 15) / 16,
      height: (outputTex.height + 15) / 16,
      depth: 1
    )
    encoder.dispatchThreadgroups(threadgroupsPerGrid: renderGroups, threadsPerThreadgroup: renderTG)
  }
}
