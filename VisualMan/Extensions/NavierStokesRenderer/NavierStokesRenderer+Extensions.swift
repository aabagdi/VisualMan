//
//  NavierStokesRenderer+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

#if !targetEnvironment(simulator)
import Metal
import os

extension NavierStokesRenderer {
  func applyBuoyancy(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(pipelines.buoyancy)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 1)
    argumentTable.setTexture(vortexField.gpuResourceID, index: 2)
    stepSinceReinit += dt * Self.advectionTimeScale
    argumentTable.setAddress(writeUniform(stepSinceReinit * Self.buoyancyStrength), index: 0)
    argumentTable.setAddress(writeUniform(Self.buoyancySettleSpeed), index: 1)
    let loudness = max(bassEnvelope, midEnvelope, highEnvelope)
    let confinement = Self.vortexConfinement * min(loudness / Self.vortexConfinementLoudness, 1)
    argumentTable.setAddress(writeUniform(stepSinceReinit * confinement), index: 2)
    dispatchGrid(encoder: encoder)
  }

  func tentFilter(encoder: any MTL4ComputeCommandEncoder,
                  src: MTLTexture,
                  dst: MTLTexture,
                  tapStep: Float) {
    encoder.setComputePipelineState(pipelines.tentFilter)
    argumentTable.setTexture(src.gpuResourceID, index: 0)
    argumentTable.setTexture(dst.gpuResourceID, index: 1)
    argumentTable.setAddress(writeUniform(tapStep), index: 0)
    dispatchGrid(encoder: encoder, width: dst.width, height: dst.height)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
  }

  func smoothDyeVelocity(encoder: any MTL4ComputeCommandEncoder) {
    tentFilter(encoder: encoder, src: velocityA, dst: dyeVelocityA, tapStep: 2)
    tentFilter(encoder: encoder, src: dyeVelocityA, dst: dyeVelocityB, tapStep: Self.dyeVelocitySmoothing)
  }

  func findVortices(encoder: any MTL4ComputeCommandEncoder) {
    tentFilter(encoder: encoder, src: dyeVelocityB, dst: vortexFlowA, tapStep: 1)
    tentFilter(encoder: encoder, src: vortexFlowA, dst: vortexFlowB, tapStep: 1)

    let uniforms = VortexUniforms(cells: Float(gridWidth) / Float(vortexField.width),
                                  floor: Self.vortexConfinementFloor,
                                  cap: Self.vortexConfinementCap,
                                  swirlScale: Self.renderCloudVortexScale)
    encoder.setComputePipelineState(pipelines.vortexField)
    argumentTable.setTexture(vortexFlowB.gpuResourceID, index: 0)
    argumentTable.setTexture(vortexField.gpuResourceID, index: 1)
    argumentTable.setAddress(writeUniform(uniforms), index: 0)
    dispatchGrid(encoder: encoder, width: vortexField.width, height: vortexField.height)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
  }

  func lightCloud(encoder: any MTL4ComputeCommandEncoder) {
    let uniforms = CloudUniforms(
      advectStep: dt * Self.advectionTimeScale,
      regrow: 1 - exp(-dt / Self.renderCloudBillowRegrowTime),
      time: time,
      billow: Self.renderCloudBillow,
      billowScale: Self.renderCloudBillowScale,
      shadow: Self.renderCloudShadow,
      relief: Self.renderCloudRelief,
      cavity: Self.renderCloudCavity,
      ambient: Self.renderCloudAmbient,
      sun: Self.renderCloudSun,
      thickness: Self.renderCloudThickness,
      vortexLift: Self.renderCloudVortexLift,
      vortexPresence: Self.renderCloudVortexPresence)
    let uniformsAddress = writeUniform(uniforms)

    encoder.setComputePipelineState(pipelines.cloudDensity)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeVelocityB.gpuResourceID, index: 1)
    argumentTable.setTexture(cloudBillowA.gpuResourceID, index: 2)
    argumentTable.setTexture(cloudBillowB.gpuResourceID, index: 3)
    argumentTable.setTexture(cloudDensity[0].gpuResourceID, index: 4)
    argumentTable.setTexture(vortexField.gpuResourceID, index: 5)
    argumentTable.setAddress(uniformsAddress, index: 0)
    dispatchGrid(encoder: encoder, width: cloudDensity[0].width, height: cloudDensity[0].height)
    swap(&cloudBillowA, &cloudBillowB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    for level in 1..<cloudDensity.count {
      tentFilter(encoder: encoder, src: cloudDensity[level - 1], dst: cloudDensity[level], tapStep: 1)
    }

    encoder.setComputePipelineState(pipelines.cloudLight)
    for (index, texture) in cloudDensity.enumerated() {
      argumentTable.setTexture(texture.gpuResourceID, index: index)
    }
    argumentTable.setTexture(cloudLight.gpuResourceID, index: cloudDensity.count)
    argumentTable.setAddress(uniformsAddress, index: 0)
    dispatchGrid(encoder: encoder, width: cloudLight.width, height: cloudLight.height)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
  }

  func advectPsi(encoder: any MTL4ComputeCommandEncoder, stepFraction: Float = 1) {
    encoder.setComputePipelineState(pipelines.psiAdvect)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(psiA.gpuResourceID, index: 1)
    argumentTable.setTexture(psiB.gpuResourceID, index: 2)
    argumentTable.setAddress(writeUniform(dt * Self.advectionTimeScale * stepFraction), index: 0)
    let traceLimits = SIMD2<Float>(Self.flowMapTraceStepCells, Self.flowMapTraceMaxSteps)
    argumentTable.setAddress(writeUniform(traceLimits), index: 1)
    dispatchGrid(encoder: encoder)
  }

  func covectorPullback(encoder: any MTL4ComputeCommandEncoder,
                        psi: MTLTexture,
                        dissipation: Float,
                        statsAddress: MTLGPUAddress) {
    encoder.setComputePipelineState(pipelines.covectorPullback)
    argumentTable.setTexture(psi.gpuResourceID, index: 0)
    argumentTable.setTexture(u0.gpuResourceID, index: 1)
    argumentTable.setTexture(velocityB.gpuResourceID, index: 2)
    argumentTable.setAddress(writeUniform(dissipation), index: 0)
    argumentTable.setAddress(statsAddress, index: 1)
    argumentTable.setAddress(writeUniform(Self.flowMapStretchThreshold), index: 2)
    argumentTable.setAddress(writeUniform(Self.maxSpeed), index: 3)
    dispatchGrid(encoder: encoder)
  }

  func predictMidStepVelocity(encoder: any MTL4ComputeCommandEncoder, dissipation: Float) {
    advectPsi(encoder: encoder, stepFraction: 0.5)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    covectorPullback(encoder: encoder, psi: psiB, dissipation: dissipation,
                     statsAddress: currentStretchStatsAddress + 8)
    swap(&velocityA, &velocityB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    gpuMark(encoder, .afterPredictorTrace)

    projectPressure(encoder: encoder, multigridCycles: Self.multigridPredictorCycles)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    gpuMark(encoder, .afterPredictorProjection)
  }

  func projectPressure(encoder: any MTL4ComputeCommandEncoder, multigridCycles: Int) {
    switch solver {
    case .jacobi:
      project(encoder: encoder, jacobiIterations: jacobiIterations)
    case .pressureMultigrid:
      projectPressureMultigrid(encoder: encoder, cycles: multigridCycles)
    }
  }

  var currentStretchStatsSlot: Int { Int(frameNumber % Self.maxFramesInFlight) }

  var currentStretchStatsAddress: MTLGPUAddress {
    stretchStatsBuffer.gpuAddress + MTLGPUAddress(currentStretchStatsSlot * Self.stretchStatsStride)
  }

  func consumeStretchStats() {
    let ptr = stretchStatsBuffer.contents() + currentStretchStatsSlot * Self.stretchStatsStride
    let stretched = ptr.load(as: UInt32.self)
    let fast = ptr.load(fromByteOffset: 4, as: UInt32.self)
    ptr.storeBytes(of: 0, as: UInt32.self)
    ptr.storeBytes(of: 0, toByteOffset: 4, as: UInt32.self)
    let dyeStray = max(ptr.load(fromByteOffset: 16, as: UInt32.self),
                       ptr.load(fromByteOffset: 20, as: UInt32.self))
    ptr.storeBytes(of: 0, toByteOffset: 16, as: UInt64.self)
    let cells = Float(gridWidth * gridHeight)
    lastStretchedFraction = Float(stretched) / cells
    lastFastFraction = Float(fast) / cells
    lastDyeStrayFraction = Float(dyeStray) / Float(dyePsiA.width * dyePsiA.height)

    statsLogCountdown -= 1
    if statsLogCountdown <= 0 {
      statsLogCountdown = 90
      let stretchedPct = lastStretchedFraction * 100
      let fastPct = lastFastFraction * 100
      let sinceReinit = framesSinceReinit
      Self.logger.info("""
        flow: stretched \(stretchedPct, format: .fixed(precision: 2))%  \
        fast \(fastPct, format: .fixed(precision: 2))%  framesSinceReinit \(sinceReinit)
        """)
    }
  }

  func shouldReinitFlowMap() -> Bool {
    if framesSinceReinit >= Self.reinitMaxInterval { return true }
    if framesSinceReinit < Self.reinitMinInterval { return false }
    return lastStretchedFraction > Self.reinitStretchFraction
  }

  func reinitFlowMap(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(pipelines.copyRG)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(u0.gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder)

    encoder.setComputePipelineState(pipelines.psiInit)
    argumentTable.setTexture(psiA.gpuResourceID, index: 0)
    dispatchGrid(encoder: encoder)
  }

  func project(encoder: any MTL4ComputeCommandEncoder, jacobiIterations: Int) {
    computeDivergence(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(pipelines.jacobiMerged)
    argumentTable.setTexture(pressure.gpuResourceID, index: 0)
    argumentTable.setTexture(divergenceTexture.gpuResourceID, index: 1)

    let mergedIterations = max(jacobiIterations / 2, 2)
    for _ in 0..<mergedIterations {
      dispatchGrid(encoder: encoder)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }

    gradientSubtract(encoder: encoder, pressure: pressure)
  }

  func computeDivergence(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(pipelines.divergence)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(divergenceTexture.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  func gradientSubtract(encoder: any MTL4ComputeCommandEncoder, pressure: MTLTexture) {
    encoder.setComputePipelineState(pipelines.gradientSubtract)
    argumentTable.setTexture(pressure.gpuResourceID, index: 0)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 1)
    argumentTable.setAddress(writeUniform(Self.maxSpeed), index: 0)

    dispatchGrid(encoder: encoder)
  }
  
  func render(encoder: any MTL4ComputeCommandEncoder,
              historyIn: MTLTexture,
              historyOut: MTLTexture) {
    encoder.setComputePipelineState(pipelines.render)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(cloudLight.gpuResourceID, index: 1)
    argumentTable.setTexture(bloomA.gpuResourceID, index: 2)
    argumentTable.setTexture(bloomMidA.gpuResourceID, index: 3)
    argumentTable.setTexture(bloomLoA.gpuResourceID, index: 4)
    argumentTable.setTexture(historyIn.gpuResourceID, index: 5)
    argumentTable.setTexture(historyOut.gpuResourceID, index: 6)
    argumentTable.setTexture(technicolorLUT.gpuResourceID, index: 7)
    argumentTable.setTexture(halationA.gpuResourceID, index: 8)
    argumentTable.setTexture(technicolorGrain.gpuResourceID, index: 9)
    argumentTable.setAddress(frameUniformsAddress, index: 0)

    dispatchGrid(encoder: encoder, width: historyOut.width, height: historyOut.height)
  }

  func makeFrameUniforms(bass: Float, mid: Float, high: Float, audioEnergy: Float) -> FrameUniforms {
    let blendPerFrame60 = max(0.55, taaBlendFactor - audioEnergy * 0.30)
    let blend = dt > 0 ? pow(blendPerFrame60, dt * 60.0) : blendPerFrame60
    let targetCeiling = max(1, min(displayHeadroom, Self.renderTechnicolorMaxHeadroom))
    technicolorCeiling += (targetCeiling - technicolorCeiling) * (1 - exp(-dt / 0.5))
    return FrameUniforms(
      bass: bass, mid: mid, high: high,
      time: time, dt: dt,
      taaBlend: blend,
      historyValid: taaHistoryValid ? 1 : 0,
      bloom: Self.renderBloomStrength,
      shading: Self.renderShading,
      detail: Self.renderDetail,
      jitter: Self.renderJitter,
      thinFade: Self.renderThinFade,
      technicolorPresence: Self.renderTechnicolorPresence,
      technicolorNeutralReach: Self.renderTechnicolorNeutralReach,
      technicolorLampGain: Self.renderTechnicolorLampGain
        * (1 + (technicolorCeiling - 1) * Self.renderTechnicolorHeadroomLamp),
      technicolorCeiling: technicolorCeiling,
      technicolorTheme: SIMD4<Float>(technicolorThemeDye, 0),
      technicolorMisregistration: Self.technicolorMisregistrationShift,
      technicolorMisregistrationWarp: Self.technicolorMisregistrationWarp,
      technicolorGateWeave: technicolorGateWeave,
      technicolorGateJump: SIMD4<Float>(lowHalf: gateJump, highHalf: gateStep),
      technicolorHalation: Self.technicolorHalation,
      technicolorGrain: grainShift,
      technicolorDepth: SIMD4<Float>(Self.renderTechnicolorThinDepth,
                                     Self.renderTechnicolorDepthStart,
                                     Self.renderTechnicolorDepthEnd, 0)
    )
  }

  func runSimulationPass(encoder: any MTL4ComputeCommandEncoder,
                         bass: Float, mid: Float, high: Float,
                         historyIn: MTLTexture,
                         historyOut: MTLTexture) {
    let audioEnergy = min(1.0, (bass + mid + high) / 3.0)
    frameUniformsAddress = writeUniform(makeFrameUniforms(bass: bass, mid: mid, high: high,
                                                          audioEnergy: audioEnergy))
    consumeStretchStats()

    let suppress = resumeSuppressionRemaining > 0
    let dissipation = pow(Self.velocityDissipation, dt * 60.0)

    gpuTiming?.beginFrame(frameNumber: frameNumber)
    gpuMark(encoder, .frameStart)
    predictMidStepVelocity(encoder: encoder, dissipation: dissipation)

    advectPsi(encoder: encoder)
    swap(&psiA, &psiB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    covectorPullback(encoder: encoder, psi: psiA, dissipation: dissipation,
                     statsAddress: currentStretchStatsAddress)
    swap(&velocityA, &velocityB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    injectAudioSplats(encoder: encoder, bass: bass, mid: mid, high: high, suppressed: suppress)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    applyBuoyancy(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    gpuMark(encoder, .afterFlowStep)

    projectPressure(encoder: encoder, multigridCycles: Self.multigridFinalCycles)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    framesSinceReinit += 1
    if shouldReinitFlowMap() {
      reinitFlowMap(encoder: encoder)
      framesSinceReinit = 0
      stepSinceReinit = 0
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
    gpuMark(encoder, .afterProjection)

    smoothDyeVelocity(encoder: encoder)
    findVortices(encoder: encoder)
    gpuMark(encoder, .afterVortices)

    advectDyeThroughMap(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    gpuMark(encoder, .afterDyeMap)

    let dyeDecay = min(Self.dyeDissipation + bass * 0.004 + mid * 0.003, 0.997)
    diffuseDye(encoder: encoder, bass: bass, mid: mid, decay: pow(dyeDecay, dt * 60.0))
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    gpuMark(encoder, .afterDyeDiffuse)

    runBloomPasses(encoder: encoder, bass: bass, mid: mid)
    runHalationPasses(encoder: encoder, history: historyIn)
    lightCloud(encoder: encoder)
    gpuMark(encoder, .afterCloud)

    render(encoder: encoder, historyIn: historyIn, historyOut: historyOut)
    gpuMark(encoder, .afterRender)
  }

  func dispatchGrid(encoder: any MTL4ComputeCommandEncoder, width: Int? = nil, height: Int? = nil) {
    let w = width ?? gridWidth
    let h = height ?? gridHeight
    let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
    let gridDimensions = MTLSize(width: w, height: h, depth: 1)
    encoder.dispatchThreads(threadsPerGrid: gridDimensions,
                            threadsPerThreadgroup: threadGroupSize)
  }
}

#endif
