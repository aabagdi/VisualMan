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
    encoder.setComputePipelineState(pipelines.curl)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(divergenceTexture.gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(pipelines.vorticityConfinement)
    argumentTable.setTexture(divergenceTexture.gpuResourceID, index: 0)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 1)
    let dtVal: Float = dt * 40.0
    let epsilon: Float = 0.30 + bass * 0.45 + mid * 0.15
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
  
  func advectPsi(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(pipelines.psiAdvect)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(psiA.gpuResourceID, index: 1)
    argumentTable.setTexture(psiB.gpuResourceID, index: 2)
    let dtVal = dt * 40.0
    argumentTable.setAddress(writeUniform(dtVal), index: 0)
    dispatchGrid(encoder: encoder)
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

    encoder.setComputePipelineState(pipelines.jacobiRedBlack)
    argumentTable.setTexture(pressure.gpuResourceID, index: 0)
    argumentTable.setTexture(divergenceTexture.gpuResourceID, index: 1)

    let halfIterations = max(jacobiIterations / 2, 2)
    for _ in 0..<halfIterations {
      argumentTable.setAddress(writeUniform(UInt32(0)), index: 0)
      dispatchGrid(encoder: encoder)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

      argumentTable.setAddress(writeUniform(UInt32(1)), index: 0)
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
  
  func blurDyeH(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(pipelines.blurH)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  func blurDyeV(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(pipelines.blurV)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  func bloomThresholdBlurH(encoder: any MTL4ComputeCommandEncoder,
                           dst: MTLTexture,
                           size: Int) {
    encoder.setComputePipelineState(pipelines.bloomThresholdBlurH)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dst.gpuResourceID, index: 1)
    let threshold: Float = 0.8
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
      argumentTable.setTexture(output.gpuResourceID, index: 5)
      argumentTable.setTexture(output.gpuResourceID, index: 6)
    }

    argumentTable.setAddress(frameUniformsAddress, index: 0)

    dispatchGrid(encoder: encoder, width: output.width, height: output.height)
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
