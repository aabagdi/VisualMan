//
//  NavierStokesRenderer+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

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
    
    let dtVal = dt * 40.0
    argumentTable.setAddress(writeUniform(dtVal), index: 0)
    argumentTable.setAddress(writeUniform(dissipation), index: 1)
    
    dispatchGrid(encoder: encoder)
  }

  func applyVorticityConfinement(encoder: any MTL4ComputeCommandEncoder,
                                 bass: Float,
                                 mid: Float) {
    encoder.setComputePipelineState(pipelines.vorticityConfinementMerged)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    let dtVal: Float = dt * 40.0
    let epsilon: Float = 0.05 + bass * 0.50 + mid * 0.18
    argumentTable.setAddress(writeUniform(dtVal), index: 0)
    argumentTable.setAddress(writeUniform(epsilon), index: 1)
    dispatchGrid(encoder: encoder)
  }

  func advectDyeMacCormack(encoder: any MTL4ComputeCommandEncoder,
                           dissipation: Float) {
    let dtVal: Float = dt * 40.0

    advect(encoder: encoder, velocityIn: velocityA, fieldIn: dyeA,
           fieldOut: dyeB, dissipation: 1.0)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(pipelines.advect)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 1)
    argumentTable.setTexture(dyeC.gpuResourceID, index: 2)
    let negDt: Float = -dtVal
    let one: Float = 1.0
    argumentTable.setAddress(writeUniform(negDt), index: 0)
    argumentTable.setAddress(writeUniform(one), index: 1)
    dispatchGrid(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(pipelines.macCormackCorrect)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 1)
    argumentTable.setTexture(dyeC.gpuResourceID, index: 2)
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
    let base: Float = 0.025 + bass * 0.012 + mid * 0.008
    let edgeBoost: Float = 0.150 + bass * 0.050 + mid * 0.020
    argumentTable.setAddress(writeUniform(base), index: 0)
    argumentTable.setAddress(writeUniform(edgeBoost), index: 1)
    dispatchGrid(encoder: encoder)
    swap(&dyeA, &dyeB)
  }

  func advectPsiMacCormack(encoder: any MTL4ComputeCommandEncoder) {
    let dtVal: Float = dt * 40.0

    encoder.setComputePipelineState(pipelines.psiAdvect)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(psiA.gpuResourceID, index: 1)
    argumentTable.setTexture(psiB.gpuResourceID, index: 2)
    argumentTable.setAddress(writeUniform(dtVal), index: 0)
    dispatchGrid(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(psiB.gpuResourceID, index: 1)
    argumentTable.setTexture(psiC.gpuResourceID, index: 2)
    let negDt: Float = -dtVal
    argumentTable.setAddress(writeUniform(negDt), index: 0)
    dispatchGrid(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(pipelines.psiMacCormackCorrect)
    argumentTable.setTexture(psiA.gpuResourceID, index: 0)
    argumentTable.setTexture(psiB.gpuResourceID, index: 1)
    argumentTable.setTexture(psiC.gpuResourceID, index: 2)
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
    dispatchGrid(encoder: encoder)
  }

  func reinitFlowMap(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(pipelines.copyRG)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(u0.gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

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

    gradientSubtract(encoder: encoder)
  }

  func computeDivergence(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(pipelines.divergence)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(divergenceTexture.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  func gradientSubtract(encoder: any MTL4ComputeCommandEncoder) {
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
    let threshold: Float = max(0.35, 0.85 - bass * 0.40 - mid * 0.15)
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

  func render(encoder: any MTL4ComputeCommandEncoder, output: MTLTexture, bass: Float, mid: Float) {
    encoder.setComputePipelineState(pipelines.render)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(output.gpuResourceID, index: 1)
    argumentTable.setTexture(bloomA.gpuResourceID, index: 2)
    argumentTable.setTexture(bloomMidA.gpuResourceID, index: 3)
    argumentTable.setTexture(bloomLoA.gpuResourceID, index: 4)

    let usePrev = (frameNumber & 1) == 0
    let historyPrev = usePrev ? taaHistoryA : taaHistoryB
    let historyNext = usePrev ? taaHistoryB : taaHistoryA
    if let hPrev = historyPrev, let hNext = historyNext {
      argumentTable.setTexture(hPrev.gpuResourceID, index: 5)
      argumentTable.setTexture(hNext.gpuResourceID, index: 6)
    } else {
      argumentTable.setTexture(dyeA.gpuResourceID, index: 5)
      argumentTable.setTexture(output.gpuResourceID, index: 6)
    }

    argumentTable.setAddress(frameUniformsAddress, index: 0)

    dispatchGrid(encoder: encoder, width: output.width, height: output.height)
  }
  
  func runSimulationPass(encoder: any MTL4ComputeCommandEncoder,
                         bass: Float, mid: Float, high: Float,
                         output: MTLTexture) {
    let validFlag: UInt32 = taaHistoryValid ? 1 : 0
    let audioEnergy = min(1.0, (bass + mid + high) / 3.0)
    let dynamicTAABlend = max(0.55, taaBlendFactor - audioEnergy * 0.30)
    let frameUniforms = FrameUniforms(
      bass: bass, mid: mid, high: high,
      time: time, dt: dt,
      taaBlend: dynamicTAABlend,
      historyValid: validFlag
    )
    frameUniformsAddress = writeUniform(frameUniforms)

    let suppress = resumeSuppressionRemaining > 0
    let injBass  = suppress ? 0 : bass
    let injMid   = suppress ? 0 : mid
    let injHigh  = suppress ? 0 : high

    advectPsiMacCormack(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    covectorPullback(encoder: encoder, dissipation: 1.0)
    swap(&velocityA, &velocityB)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    injectAudioSplats(encoder: encoder, bass: injBass, mid: injMid, high: injHigh)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    applyVorticityConfinement(encoder: encoder, bass: injBass, mid: injMid)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    project(encoder: encoder, jacobiIterations: jacobiIterations)
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
    
    diffuseDye(encoder: encoder, bass: bass, mid: mid)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    runBloomPasses(encoder: encoder, bass: bass, mid: mid)

    render(encoder: encoder, output: output, bass: bass, mid: mid)
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
    let w = width ?? gridSize
    let h = height ?? gridSize
    let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
    let gridDimensions = MTLSize(width: w, height: h, depth: 1)
    encoder.dispatchThreads(threadsPerGrid: gridDimensions,
                            threadsPerThreadgroup: threadGroupSize)
  }
}
