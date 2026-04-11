//
//  NavierStokesRenderer+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import Metal
import os
import simd

private func hsv2rgb(h: Float, s: Float, v: Float) -> SIMD3<Float> {
  let hh = h - floor(h)
  let p = SIMD3<Float>(
    abs(hh * 6.0 - 3.0) - 1.0,
    2.0 - abs(hh * 6.0 - 2.0),
    2.0 - abs(hh * 6.0 - 4.0)
  )
  let clamped = simd_clamp(p, SIMD3<Float>(repeating: 0.0), SIMD3<Float>(repeating: 1.0))
  return v * simd_mix(SIMD3<Float>(repeating: 1.0), clamped, SIMD3<Float>(repeating: s))
}

extension NavierStokesRenderer {
  func injectAudioSplats(encoder: any MTL4ComputeCommandEncoder,
                         bass: Float,
                         mid: Float,
                         high: Float) {
    let center = Float(gridSize) * 0.5
    let gs = Float(gridSize)
    let s = gs / 1024.0

    var forceSplats: [SplatParams] = []
    var dyeSplats: [SplatParams] = []

    let audioEnergy = (bass + mid + high) / 3.0
    collectVortexSplats(center: center, s: s, audioEnergy: audioEnergy,
                        forceSplats: &forceSplats, dyeSplats: &dyeSplats)

    if bass > 0.01 {
      collectBassSplats(bass: bass, center: center, gs: gs,
                        forceSplats: &forceSplats, dyeSplats: &dyeSplats)
    }

    if mid > 0.01 {
      collectMidSplats(mid: mid, center: center, gs: gs,
                       forceSplats: &forceSplats, dyeSplats: &dyeSplats)
    }

    if high > 0.02 {
      collectHighSplats(high: high, center: center, gs: gs,
                        forceSplats: &forceSplats, dyeSplats: &dyeSplats)
    }

    if !forceSplats.isEmpty {
      dispatchBatchedSplats(encoder: encoder, texture: velocityA, splats: forceSplats)
    }
    if !dyeSplats.isEmpty {
      dispatchBatchedSplats(encoder: encoder, texture: dyeA, splats: dyeSplats)
    }

    prevBass = bass
    prevMid = mid
  }

  private func dispatchBatchedSplats(encoder: any MTL4ComputeCommandEncoder,
                                     texture: MTLTexture,
                                     splats: [SplatParams]) {
    encoder.setComputePipelineState(splatBatchPipeline)
    argumentTable.setTexture(texture.gpuResourceID, index: 0)
    argumentTable.setAddress(writeUniformArray(splats), index: 0)
    let count = UInt32(splats.count)
    argumentTable.setAddress(writeUniform(count), index: 1)
    dispatchGrid(encoder: encoder)
  }

  private func collectBassSplats(bass: Float,
                                 center: Float,
                                 gs: Float,
                                 forceSplats: inout [SplatParams],
                                 dyeSplats: inout [SplatParams]) {
    let bassForce = bass * 300.0
    let bassRadius = gs * 0.08 * (1.0 + bass * 0.5)

    let bassOnset = max(bass - prevBass, 0)
    let onsetBoost = 1.0 + bassOnset * 5.0

    let angle1 = time * 0.7
    let angle2 = angle1 + .pi
    let orbitRadius = gs * 0.15

    let pos1 = SIMD2<Float>(center + cos(angle1) * orbitRadius,
                            center + sin(angle1) * orbitRadius)
    let pos2 = SIMD2<Float>(center + cos(angle2) * orbitRadius,
                            center + sin(angle2) * orbitRadius)

    let dir1 = normalize(pos1 - SIMD2<Float>(center, center))
    let dir2 = normalize(pos2 - SIMD2<Float>(center, center))

    let force1 = SIMD3<Float>(dir1.x, dir1.y, 0) * bassForce * onsetBoost
    let force2 = SIMD3<Float>(dir2.x, dir2.y, 0) * bassForce * onsetBoost

    forceSplats.append(SplatParams(position: pos1, value: force1, radius: bassRadius))
    forceSplats.append(SplatParams(position: pos2, value: force2, radius: bassRadius))

    let bassHue = fmod(time * 0.05, 1.0)
    let bassColor = hsv2rgb(h: bassHue, s: 0.85, v: bass * 0.75) * onsetBoost
    dyeSplats.append(SplatParams(position: pos1, value: bassColor, radius: bassRadius * 1.2))
    dyeSplats.append(SplatParams(position: pos2, value: bassColor * 0.8, radius: bassRadius * 1.2))
    
    if bassOnset > 0.15 {
      let burstCount = 7
      let burstCenter = SIMD2<Float>(
        center + sin(time * 1.7) * gs * 0.1,
        center + cos(time * 2.3) * gs * 0.1
      )
      let burstForceScale = bassOnset * 500.0
      let burstRadius = gs * 0.05
      
      for i in 0..<burstCount {
        let angle = Float(i) * (.pi * 2.0 / Float(burstCount)) + time * 0.5
        let dir = SIMD2<Float>(cos(angle), sin(angle))
        let splatPos = burstCenter + dir * gs * 0.06
        
        let force = SIMD3<Float>(dir.x, dir.y, 0) * burstForceScale
        forceSplats.append(SplatParams(position: splatPos, value: force, radius: burstRadius))
        
        let burstHue = fmod(time * 0.05 + Float(i) / Float(burstCount), 1.0)
        let burstColor = hsv2rgb(h: burstHue, s: 0.95, v: bass)
        dyeSplats.append(SplatParams(position: splatPos, value: burstColor, radius: burstRadius * 1.4))
      }
    }
  }

  private func collectMidSplats(mid: Float,
                                center: Float,
                                gs: Float,
                                forceSplats: inout [SplatParams],
                                dyeSplats: inout [SplatParams]) {
    let midForce = mid * 200.0
    let midRadius = gs * 0.04 * (1.0 + mid * 0.3)

    let midOnset = max(mid - prevMid, 0)
    let midBoost = 1.0 + midOnset * 3.0

    for i in 0..<3 {
      let angle = time * 1.3 + Float(i) * (.pi * 2.0 / 3.0)
      let orbit = gs * 0.25
      let pos = SIMD2<Float>(center + cos(angle) * orbit,
                             center + sin(angle) * orbit)

      let tangent = SIMD2<Float>(-sin(angle), cos(angle))
      let force = SIMD3<Float>(tangent.x, tangent.y, 0) * midForce * midBoost

      forceSplats.append(SplatParams(position: pos, value: force, radius: midRadius))

      let midHue = fmod(time * 0.07 + Float(i) * 0.33, 1.0)
      let midColor = hsv2rgb(h: midHue, s: 0.75, v: mid * 0.6) * midBoost
      dyeSplats.append(SplatParams(position: pos, value: midColor, radius: midRadius * 1.3))
    }

    if midOnset > 0.12 {
      let burstCount = 5
      let burstForce = midOnset * 350.0
      let burstRadius = gs * 0.035
      for i in 0..<burstCount {
        let angle = Float(i) * (.pi * 2.0 / Float(burstCount)) + time * 1.5
        let dir = SIMD2<Float>(cos(angle), sin(angle))
        let splatPos = SIMD2<Float>(center, center) + dir * gs * 0.2
        let tangent = SIMD2<Float>(-dir.y, dir.x)
        let force = SIMD3<Float>(tangent.x, tangent.y, 0) * burstForce
        forceSplats.append(SplatParams(position: splatPos, value: force, radius: burstRadius))

        let hue = fmod(time * 0.07 + Float(i) * 0.2, 1.0)
        let color = hsv2rgb(h: hue, s: 0.9, v: mid * 0.8)
        dyeSplats.append(SplatParams(position: splatPos, value: color, radius: burstRadius * 1.3))
      }
    }
  }

  private func collectHighSplats(high: Float,
                                 center: Float,
                                 gs: Float,
                                 forceSplats: inout [SplatParams],
                                 dyeSplats: inout [SplatParams]) {
    let highForce = high * 120.0
    let highRadius = gs * 0.02

    for i in 0..<4 {
      let angle = time * 2.1 + Float(i) * (.pi * 0.5) + sin(time * 3.0 + Float(i)) * 0.5
      let orbit = gs * 0.35
      let pos = SIMD2<Float>(center + cos(angle) * orbit,
                             center + sin(angle) * orbit)

      let dir = SIMD2<Float>(cos(angle + Float(i)), sin(angle + Float(i)))
      let force = SIMD3<Float>(dir.x, dir.y, 0) * highForce

      forceSplats.append(SplatParams(position: pos, value: force, radius: highRadius))

      let highHue = fmod(time * 0.09 + Float(i) * 0.25, 1.0)
      let highColor = hsv2rgb(h: highHue, s: 0.9, v: high)
      dyeSplats.append(SplatParams(position: pos, value: highColor, radius: highRadius * 1.5))
    }
  }

  private func collectVortexSplats(center: Float,
                                   s: Float,
                                   audioEnergy: Float,
                                   forceSplats: inout [SplatParams],
                                   dyeSplats: inout [SplatParams]) {
    let vortexAngle = time * 0.3
    let vortexR: Float = 80.0 * s
    let strength: Float = 200.0 * s * (0.3 + audioEnergy * 0.7)
    for i in 0..<2 {
      let a = vortexAngle + Float(i) * .pi
      let pos = SIMD2<Float>(center + cos(a) * vortexR, center + sin(a) * vortexR)
      forceSplats.append(SplatParams(position: pos,
                                     value: SIMD3<Float>(-sin(a) * strength, cos(a) * strength, 0),
                                     radius: 100.0 * s))
    }
    let hue = fmod(time * 0.1, 1.0)
    let color = SIMD3<Float>(
      0.3 + 0.2 * sin(hue * .pi * 2.0),
      0.15 + 0.2 * sin(hue * .pi * 2.0 + 2.094),
      0.25 + 0.2 * sin(hue * .pi * 2.0 + 4.189)
    )
    dyeSplats.append(SplatParams(position: SIMD2<Float>(center, center),
                                 value: color * (0.3 + audioEnergy * 0.7),
                                 radius: 90.0 * s))
  }
  
  func advect(encoder: any MTL4ComputeCommandEncoder,
              velocityIn: MTLTexture,
              fieldIn: MTLTexture,
              fieldOut: MTLTexture,
              dissipation: Float) {
    encoder.setComputePipelineState(advectPipeline)
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
    encoder.setComputePipelineState(curlPipeline)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(divergenceTexture.gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(vorticityConfinementPipeline)
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

    encoder.setComputePipelineState(advectPipeline)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 1)
    argumentTable.setTexture(dyeC.gpuResourceID, index: 2)
    let negDt: Float = -dtVal
    let one: Float = 1.0
    argumentTable.setAddress(writeUniform(negDt), index: 0)
    argumentTable.setAddress(writeUniform(one), index: 1)
    dispatchGrid(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(macCormackCorrectPipeline)
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
    encoder.setComputePipelineState(psiAdvectPipeline)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(psiA.gpuResourceID, index: 1)
    argumentTable.setTexture(psiB.gpuResourceID, index: 2)
    let dtVal = dt * 40.0
    argumentTable.setAddress(writeUniform(dtVal), index: 0)
    dispatchGrid(encoder: encoder)
  }

  func covectorPullback(encoder: any MTL4ComputeCommandEncoder,
                        dissipation: Float) {
    encoder.setComputePipelineState(covectorPullbackPipeline)
    argumentTable.setTexture(psiA.gpuResourceID, index: 0)
    argumentTable.setTexture(u0.gpuResourceID, index: 1)
    argumentTable.setTexture(velocityB.gpuResourceID, index: 2)
    argumentTable.setAddress(writeUniform(dissipation), index: 0)
    dispatchGrid(encoder: encoder)
  }

  func reinitFlowMap(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(copyRGPipeline)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(u0.gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(psiInitPipeline)
    argumentTable.setTexture(psiA.gpuResourceID, index: 0)
    dispatchGrid(encoder: encoder)
  }
  
  func project(encoder: any MTL4ComputeCommandEncoder, jacobiIterations: Int) {
    computeDivergence(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(jacobiRedBlackPipeline)
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
    encoder.setComputePipelineState(divergencePipeline)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(divergenceTexture.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  func gradientSubtract(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(gradientSubtractPipeline)
    argumentTable.setTexture(pressure.gpuResourceID, index: 0)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  func blurDyeH(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(blurHPipeline)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  func blurDyeV(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(blurVPipeline)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  func bloomThresholdBlurH(encoder: any MTL4ComputeCommandEncoder,
                           dst: MTLTexture,
                           size: Int) {
    encoder.setComputePipelineState(bloomThresholdBlurHPipeline)
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
    encoder.setComputePipelineState(blurVPipeline)
    argumentTable.setTexture(src.gpuResourceID, index: 0)
    argumentTable.setTexture(dst.gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder, width: size, height: size)
  }
  
  func render(encoder: any MTL4ComputeCommandEncoder, output: MTLTexture, bass: Float, mid: Float) {
    encoder.setComputePipelineState(renderPipeline)
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

    argumentTable.setAddress(writeUniform(bass), index: 0)
    argumentTable.setAddress(writeUniform(mid), index: 1)
    argumentTable.setAddress(writeUniform(time), index: 2)
    argumentTable.setAddress(writeUniform(taaBlendFactor), index: 3)
    let validFlag: UInt32 = (taaHistoryValid && historyPrev != nil) ? 1 : 0
    argumentTable.setAddress(writeUniform(validFlag), index: 4)

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
