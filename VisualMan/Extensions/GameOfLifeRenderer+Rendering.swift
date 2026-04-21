//
//  GameOfLifeRenderer+Rendering.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/14/26.
//

import Metal
import QuartzCore

extension GameOfLifeRenderer {
  func encodeFrame(bass: Float, mid: Float, high: Float, drawableTexture: MTLTexture) -> MTLTexture? {
    drainPendingTextureReleases()

    ensureSimTextures(drawableWidth: drawableTexture.width,
                      drawableHeight: drawableTexture.height)
    guard let localSimA = simA, let localSimB = simB else {
      return nil
    }

    guard ensureDisplayIntermediate(width: drawableTexture.width,
                                    height: drawableTexture.height),
          let displayTex = displayIntermediate else {
      return nil
    }

    renderFrameCount += 1
    time += dt

    let (shouldStep, params) = updateAudioAndParams(bass: bass, mid: mid, high: high)

    guard let encoder = beginFrame() else { return nil }

    if shouldStep {
      stepAccumulator = 0
      simFrameCount += 1
      encodeStep(encoder: encoder, simA: localSimA, simB: localSimB, params: params)
    }

    let simSource = shouldStep ? localSimB : localSimA
    encodeRender(encoder: encoder, simSource: simSource, outputTex: displayTex, params: params)

    encoder.endEncoding()

    pendingShouldStep = shouldStep
    return displayTex
  }

  func commitFrame(intermediateTexture: MTLTexture, drawable: CAMetalDrawable) {
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
      commandBuffer.endCommandBuffer()
      return
    }
    encoder.barrier(afterQueueStages: .dispatch, beforeStages: .blit)
    encoder.copy(sourceTexture: intermediateTexture, destinationTexture: drawable.texture)
    encoder.endEncoding()
    commandBuffer.endCommandBuffer()

    commandQueue.waitForDrawable(drawable)
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: frameNumber)
    commandQueue.signalDrawable(drawable)
    drawable.present()

    if pendingShouldStep {
      swap(&simA, &simB)
      pendingShouldStep = false
    }
  }

  func updateAudioAndParams(bass: Float, mid: Float, high: Float) ->
  (shouldStep: Bool, params: GameOfLifeParams) {
    if needsAudioReseed {
      smoothedBass = bass
      smoothedMid = mid
      needsAudioReseed = false
    } else {
      let bassTau: Float = bass > smoothedBass ? 0.04 : 0.15
      let midTau: Float = mid > smoothedMid ? 0.05 : 0.18
      smoothedBass += (bass - smoothedBass) * (1 - exp(-dt / bassTau))
      smoothedMid += (mid - smoothedMid) * (1 - exp(-dt / midTau))
    }

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

  func encodeStep(encoder: some MTL4ComputeCommandEncoder,
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

  func encodeRender(encoder: some MTL4ComputeCommandEncoder,
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
