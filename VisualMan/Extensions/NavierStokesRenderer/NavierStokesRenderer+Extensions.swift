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
  func advect(encoder: any MTL4ComputeCommandEncoder,
              velocityIn: MTLTexture,
              fieldIn: MTLTexture,
              fieldOut: MTLTexture,
              dissipation: Float) {
    encoder.setComputePipelineState(pipelines.advect)
    argumentTable.setTexture(velocityIn.gpuResourceID, index: 0)
    argumentTable.setTexture(fieldIn.gpuResourceID, index: 1)
    argumentTable.setTexture(fieldOut.gpuResourceID, index: 2)

    let dtVal = dt * Self.advectionTimeScale
    argumentTable.setAddress(writeUniform(dtVal), index: 0)
argumentTable.setAddress(writeUniform(dissipation), index: 1)
    
    dispatchGrid(encoder: encoder)
  }

  func applyVorticityConfinement(encoder: any MTL4ComputeCommandEncoder,
                                 bass: Float,
                                 mid: Float) {
    encoder.setComputePipelineState(pipelines.vorticityConfinementMerged)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 1)
    let dtVal: Float = dt * Self.advectionTimeScale * 0.5
    let epsilon: Float = (0.05 + bass * 0.50 + mid * 0.18) * Self.vorticityConfinementScale
      * (1.0 + Self.excitementConfinementGain * lastExcitement)
    argumentTable.setAddress(writeUniform(dtVal), index: 0)
    argumentTable.setAddress(writeUniform(epsilon), index: 1)
    argumentTable.setAddress(writeUniform(Self.buoyancyStrength), index: 2)
    argumentTable.setAddress(writeUniform(Self.buoyancySettleSpeed), index: 3)
    dispatchGrid(encoder: encoder)
  }

  func advectDyeMacCormack(encoder: any MTL4ComputeCommandEncoder,
                           dissipation: Float) {
    let dtVal: Float = dt * Self.advectionTimeScale

    advect(encoder: encoder, velocityIn: velocityA, fieldIn: dyeA,
           fieldOut: dyeB, dissipation: 1.0)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(pipelines.macCormackCorrect)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 1)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 3)
    argumentTable.setTexture(dyeC.gpuResourceID, index: 4)
    argumentTable.setAddress(writeUniform(dtVal), index: 0)
    argumentTable.setAddress(writeUniform(dissipation), index: 1)
    dispatchGrid(encoder: encoder)

    swap(&dyeA, &dyeC)
  }

  func diffuseDye(encoder: any MTL4ComputeCommandEncoder,
                  bass: Float,
                  mid: Float) {
    encoder.setComputePipelineState(pipelines.dyeDiffuse)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 1)
    let base: Float = Self.dyeDiffusionBase + bass * 0.012 + mid * 0.008
    let edgeBoost: Float = 0.150 + bass * 0.050 + mid * 0.020
    argumentTable.setAddress(writeUniform(base), index: 0)
    argumentTable.setAddress(writeUniform(edgeBoost), index: 1)
    let edgeRate = 1.0 - pow(1.0 - Self.dyeEdgeFadeRate, dt * 60.0)
    argumentTable.setAddress(writeUniform(SIMD2<Float>(Self.dyeEdgeFadeCells, edgeRate)), index: 2)
    dispatchGrid(encoder: encoder)
    swap(&dyeA, &dyeB)
  }

  func advectPsiMacCormack(encoder: any MTL4ComputeCommandEncoder) {
    let dtVal: Float = dt * Self.advectionTimeScale

    encoder.setComputePipelineState(pipelines.psiAdvect)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(psiA.gpuResourceID, index: 1)
    argumentTable.setTexture(psiB.gpuResourceID, index: 2)
    argumentTable.setAddress(writeUniform(dtVal), index: 0)
    dispatchGrid(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(pipelines.psiMacCormackCorrect)
    argumentTable.setTexture(psiA.gpuResourceID, index: 0)
    argumentTable.setTexture(psiB.gpuResourceID, index: 1)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 3)
    argumentTable.setTexture(psiC.gpuResourceID, index: 4)
    argumentTable.setAddress(writeUniform(dtVal), index: 0)
    dispatchGrid(encoder: encoder)

    swap(&psiA, &psiC)
  }

  func covectorPullback(encoder: any MTL4ComputeCommandEncoder,
                        dissipation: Float) {
    encoder.setComputePipelineState(pipelines.covectorPullback)
    argumentTable.setTexture(psiA.gpuResourceID, index: 0)
    argumentTable.setTexture(u0.gpuResourceID, index: 1)
    argumentTable.setTexture(velocityB.gpuResourceID, index: 2)
    argumentTable.setAddress(writeUniform(dissipation), index: 0)
    argumentTable.setAddress(currentStretchStatsAddress, index: 1)
    argumentTable.setAddress(writeUniform(Self.flowMapStretchThreshold), index: 2)
    argumentTable.setAddress(writeUniform(Self.maxSpeed), index: 3)
    dispatchGrid(encoder: encoder)
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
    let cells = Float(gridWidth * gridHeight)
    lastStretchedFraction = Float(stretched) / cells
    lastFastFraction = Float(fast) / cells

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

  func applyViscosity(encoder: any MTL4ComputeCommandEncoder, alpha: Float) {
    encoder.setComputePipelineState(pipelines.viscosity)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(velocityB.gpuResourceID, index: 1)
    argumentTable.setAddress(writeUniform(alpha), index: 0)
    argumentTable.setAddress(writeUniform(Self.maxSpeed), index: 1)
    dispatchGrid(encoder: encoder)
    swap(&velocityA, &velocityB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
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
    
    dispatchGrid(encoder: encoder)
  }
  
  func bloomThresholdBlurH(encoder: any MTL4ComputeCommandEncoder,
                           dst: MTLTexture,
                           size: Int,
                           bass: Float,
                           mid: Float) {
    encoder.setComputePipelineState(pipelines.bloomThresholdBlurH)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dst.gpuResourceID, index: 1)
    let threshold: Float = max(0.50, 1.21 - bass * 0.57 - mid * 0.21)
    argumentTable.setAddress(writeUniform(threshold), index: 0)
    dispatchGrid(encoder: encoder, width: size, height: size)
  }

  func blurBloomV(encoder: any MTL4ComputeCommandEncoder,
                  src: MTLTexture,
                  dst: MTLTexture,
                  size: Int) {
    encoder.setComputePipelineState(pipelines.blurV)
    argumentTable.setTexture(src.gpuResourceID, index: 0)
    argumentTable.setTexture(dst.gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder, width: size, height: size)
  }

  func bloomDownsample(encoder: any MTL4ComputeCommandEncoder,
                       src: MTLTexture,
                       dst: MTLTexture,
                       dstSize: Int) {
    encoder.setComputePipelineState(pipelines.bloomDownsample)
    argumentTable.setTexture(src.gpuResourceID, index: 0)
    argumentTable.setTexture(dst.gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder, width: dstSize, height: dstSize)
  }

  func render(encoder: any MTL4ComputeCommandEncoder,
              historyIn: MTLTexture,
              historyOut: MTLTexture) {
    encoder.setComputePipelineState(pipelines.render)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(bloomA.gpuResourceID, index: 2)
    argumentTable.setTexture(bloomMidA.gpuResourceID, index: 3)
    argumentTable.setTexture(bloomLoA.gpuResourceID, index: 4)
    argumentTable.setTexture(historyIn.gpuResourceID, index: 5)
    argumentTable.setTexture(historyOut.gpuResourceID, index: 6)
    argumentTable.setTexture(technicolorLUT.gpuResourceID, index: 7)
    argumentTable.setAddress(frameUniformsAddress, index: 0)

    dispatchGrid(encoder: encoder, width: historyOut.width, height: historyOut.height)
  }

  func energyBudget(audioEnergy: Float) -> (dissipation: Float, viscosity: Float) {
    let frameScale = dt * 60.0
    let dissipation = pow(Self.velocityDissipation, frameScale)
    let calm = 1.0 - Self.excitementViscosityReduction * lastExcitement
    let viscosityBase = max(0, Self.velocityViscosity * calm - audioEnergy * Self.viscosityAudioReduction)
    let viscosity = 1.0 - pow(1.0 - min(viscosityBase, 1.0), frameScale)
    return (dissipation, viscosity)
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
      technicolorMisregistration: technicolorMisregistration(bass: bass, high: high),
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
    let injBass  = suppress ? 0 : bass
    let injMid   = suppress ? 0 : mid

    let (dissipation, viscosity) = energyBudget(audioEnergy: audioEnergy)

    advectPsiMacCormack(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    covectorPullback(encoder: encoder, dissipation: dissipation)
    swap(&velocityA, &velocityB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    injectAudioSplats(encoder: encoder, bass: bass, mid: mid, high: high, suppressed: suppress)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    applyVorticityConfinement(encoder: encoder, bass: injBass, mid: injMid)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    switch solver {
    case .jacobi:
      project(encoder: encoder, jacobiIterations: jacobiIterations)
    case .pressureMultigrid:
      projectPressureMultigrid(encoder: encoder)
    }
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    applyViscosity(encoder: encoder, alpha: viscosity)

    framesSinceReinit += 1
    if shouldReinitFlowMap() {
      reinitFlowMap(encoder: encoder)
      framesSinceReinit = 0
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }

    let dyeDecay = min(Self.dyeDissipation + bass * 0.004 + mid * 0.003, 0.997)
    advectDyeMacCormack(encoder: encoder, dissipation: pow(dyeDecay, dt * 60.0))
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    diffuseDye(encoder: encoder, bass: bass, mid: mid)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    runBloomPasses(encoder: encoder, bass: bass, mid: mid)

    render(encoder: encoder, historyIn: historyIn, historyOut: historyOut)
  }

  func runBloomPasses(encoder: any MTL4ComputeCommandEncoder,
                      bass: Float,
                      mid: Float) {
    bloomThresholdBlurH(encoder: encoder, dst: bloomB, size: Self.bloomSize,
                        bass: bass, mid: mid)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    blurBloomV(encoder: encoder, src: bloomB, dst: bloomA, size: Self.bloomSize)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    bloomDownsample(encoder: encoder, src: bloomA, dst: bloomMidA, dstSize: Self.bloomSizeMid)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    bloomDownsample(encoder: encoder, src: bloomMidA, dst: bloomLoA, dstSize: Self.bloomSizeLo)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
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
