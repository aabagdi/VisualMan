//
//  NavierStokesRenderer+DyeMap.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/15/26.
//

#if !targetEnvironment(simulator)
import Metal

extension NavierStokesRenderer {
  func advectDyeThroughMap(encoder: any MTL4ComputeCommandEncoder) {
    resetOrAccumulateDyeMap(encoder: encoder)
    advanceDyeMap(encoder: encoder)
    lookUpDyeWithBFECC(encoder: encoder)
  }

  func resetOrAccumulateDyeMap(encoder: any MTL4ComputeCommandEncoder) {
    framesSinceDyeReinit += 1
    if shouldReinitDyeMap() {
      encoder.setComputePipelineState(pipelines.dyeMapReset)
      argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
      argumentTable.setTexture(dye0.gpuResourceID, index: 1)
      argumentTable.setTexture(dyePsiA.gpuResourceID, index: 2)
      argumentTable.setTexture(dyePhiA.gpuResourceID, index: 3)
      framesSinceDyeReinit = 0
    } else {
      encoder.setComputePipelineState(pipelines.dyeMapAccumulate)
      argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
      argumentTable.setTexture(dyeB.gpuResourceID, index: 1)
      argumentTable.setTexture(dyePhiA.gpuResourceID, index: 2)
      argumentTable.setTexture(dye0.gpuResourceID, index: 3)
    }
    dispatchGrid(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
  }

  func advanceDyeMap(encoder: any MTL4ComputeCommandEncoder) {
    let uniforms = DyeMapUniforms(
      gridSize: SIMD2<Float>(Float(gridWidth), Float(gridHeight)),
      traceLimits: SIMD2<Float>(Self.flowMapTraceStepCells, Self.flowMapTraceMaxSteps),
      dt: dt * Self.advectionTimeScale,
      strayCells: Self.dyeMapStrayCells)
    encoder.setComputePipelineState(pipelines.dyeMapAdvance)
    argumentTable.setTexture(dyeVelocityB.gpuResourceID, index: 0)
    argumentTable.setTexture(dyePsiA.gpuResourceID, index: 1)
    argumentTable.setTexture(dyePhiA.gpuResourceID, index: 2)
    argumentTable.setTexture(dyePsiB.gpuResourceID, index: 3)
    argumentTable.setTexture(dyePhiB.gpuResourceID, index: 4)
    argumentTable.setAddress(writeUniform(uniforms), index: 0)
    argumentTable.setAddress(currentStretchStatsAddress + 16, index: 1)
    dispatchGrid(encoder: encoder, width: dyePsiA.width, height: dyePsiA.height)
    swap(&dyePsiA, &dyePsiB)
    swap(&dyePhiA, &dyePhiB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
  }

  func lookUpDyeWithBFECC(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(pipelines.dyeMapLookup)
    argumentTable.setTexture(dyePsiA.gpuResourceID, index: 0)
    argumentTable.setTexture(dye0.gpuResourceID, index: 1)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 2)
    dispatchGrid(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(pipelines.dyeMapError)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dye0.gpuResourceID, index: 1)
    argumentTable.setTexture(dyePhiA.gpuResourceID, index: 2)
    argumentTable.setTexture(dyeC.gpuResourceID, index: 3)
    dispatchGrid(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(pipelines.dyeMapCorrect)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeC.gpuResourceID, index: 1)
    argumentTable.setTexture(dyePsiA.gpuResourceID, index: 2)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 3)
    dispatchGrid(encoder: encoder)
  }

  func shouldReinitDyeMap() -> Bool {
    if framesSinceDyeReinit >= Self.dyeMapMaxInterval { return true }
    if framesSinceDyeReinit < Self.dyeMapMinInterval { return false }
    return lastDyeStrayFraction > Self.dyeMapStrayFraction
  }

  func diffuseDye(encoder: any MTL4ComputeCommandEncoder,
                  bass: Float,
                  mid: Float,
                  decay: Float) {
    encoder.setComputePipelineState(pipelines.dyeDiffuse)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 1)
    let base: Float = Self.dyeDiffusionBase + bass * 0.006 + mid * 0.004
    let edgeBoost: Float = 0.075 + bass * 0.025 + mid * 0.010
    argumentTable.setAddress(writeUniform(base), index: 0)
    argumentTable.setAddress(writeUniform(edgeBoost), index: 1)
    let edgeRate = 1.0 - pow(1.0 - Self.dyeEdgeFadeRate, dt * 60.0)
    argumentTable.setAddress(writeUniform(SIMD2<Float>(Self.dyeEdgeFadeCells, edgeRate)), index: 2)
    argumentTable.setAddress(writeUniform(decay), index: 3)
    dispatchGrid(encoder: encoder)
  }
}

#endif
