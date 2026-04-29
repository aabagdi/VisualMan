//
//  AbstractExpressionismRenderer+Rendering.swift
//  VisualMan
//
//  Created by on 4/23/26.
//

import Metal
import QuartzCore

extension AbstractExpressionismRenderer {
  private func handleResumeState(gap: Double) {
    let gapResume = gap > 0.2
    let isResume = (lastFrameTime == 0) || gapResume
    if isResume {
      dt = 0
      if gapResume {
        resumeSuppressionRemaining = Self.resumeFadeDuration
        envelope = .zero
        slowEnvelope = .zero
        smoothedBass = 0
        if gap > 2.0 { resumeFadeIn = 0 }
      }
    } else {
      dt = Float(max(1.0 / 240.0, min(1.0 / 30.0, gap)))
    }
  }

  func processAudio(bass: Float, mid: Float, high: Float) -> SIMD3<Float> {
    let now = CACurrentMediaTime()
    let gap = lastFrameTime == 0 ? 0 : (now - lastFrameTime)
    handleResumeState(gap: gap)
    lastFrameTime = now
    wallClock += dt
    time += dt
    resumeSuppressionRemaining = max(0, resumeSuppressionRemaining - dt)

    let input = SIMD3<Float>(bass, mid, high)
    let fastA = 1 - exp(-dt / 0.015)
    let fastD = 1 - exp(-dt / 0.15)
    var fastRate = SIMD3<Float>(repeating: fastD)
    fastRate.replace(with: SIMD3<Float>(repeating: fastA), where: input .> envelope)
    envelope += (input - envelope) * fastRate

    let slowA = 1 - exp(-dt / 0.4)
    slowEnvelope += (input - slowEnvelope) * slowA

    let bassA = 1 - exp(-dt / (bass > smoothedBass ? 0.06 : 0.25))
    smoothedBass += (bass - smoothedBass) * bassA

    hueOffset += dt * 0.02

    let atmTarget = min(1.0, ((slowEnvelope.x + slowEnvelope.y + slowEnvelope.z) / 3.0) * 1.6)
    let atmRate = 1 - exp(-dt / (atmTarget > atmosphereIntensity ? 1.5 : 3.0))
    atmosphereIntensity += (atmTarget - atmosphereIntensity) * atmRate

    atmosphereHue = (atmosphereHue + dt * 0.0033).truncatingRemainder(dividingBy: 1.0)

    if resumeFadeIn < 1 {
      resumeFadeIn = min(1, resumeFadeIn + dt / Self.resumeFadeDuration)
    }
    let u = resumeFadeIn
    let fade = u * u * (3 - 2 * u)
    return envelope * fade
  }

  func renderPaint(encoder: any MTL4ComputeCommandEncoder,
                   colorIn: MTLTexture, colorOut: MTLTexture,
                   hwIn: MTLTexture, hwOut: MTLTexture,
                   velocityIn: MTLTexture,
                   params: AbExParams, strokes: [AbExStroke],
                   tileMap: TileMap) {
    encoder.setComputePipelineState(paintPipeline)
    argumentTable.setTexture(colorIn.gpuResourceID, index: 0)
    argumentTable.setTexture(colorOut.gpuResourceID, index: 1)
    argumentTable.setTexture(hwIn.gpuResourceID, index: 2)
    argumentTable.setTexture(hwOut.gpuResourceID, index: 3)
    argumentTable.setTexture(velocityIn.gpuResourceID, index: 4)
    argumentTable.setAddress(writeUniform(params), index: 0)

    if strokes.isEmpty {
      let empty = AbExStroke(posAngle: .zero, sizeOpacity: .zero,
                              color: .zero, animation: .zero)
      argumentTable.setAddress(writeUniform(empty), index: 1)
    } else {
      argumentTable.setAddress(writeUniformArray(strokes), index: 1)
    }
    argumentTable.setAddress(writeUniformArray(tileMap.counts), index: 2)
    argumentTable.setAddress(writeUniformArray(tileMap.indices), index: 3)

    let tg = MTLSize(width: 32, height: 16, depth: 1)
    let grid = MTLSize(width: colorOut.width, height: colorOut.height, depth: 1)
    encoder.dispatchThreads(threadsPerGrid: grid, threadsPerThreadgroup: tg)
  }

  func renderVelocityDeposit(encoder: any MTL4ComputeCommandEncoder,
                             velocityIn: MTLTexture, velocityOut: MTLTexture,
                             heightWetIn: MTLTexture,
                             params: AbExParams, strokes: [AbExStroke],
                             tileMap: TileMap) {
    encoder.setComputePipelineState(velocityPipeline)
    argumentTable.setTexture(velocityIn.gpuResourceID, index: 0)
    argumentTable.setTexture(velocityOut.gpuResourceID, index: 1)
    argumentTable.setTexture(heightWetIn.gpuResourceID, index: 2)
    argumentTable.setAddress(writeUniform(params), index: 0)

    if strokes.isEmpty {
      let empty = AbExStroke(posAngle: .zero, sizeOpacity: .zero,
                              color: .zero, animation: .zero)
      argumentTable.setAddress(writeUniform(empty), index: 1)
    } else {
      argumentTable.setAddress(writeUniformArray(strokes), index: 1)
    }
    argumentTable.setAddress(writeUniformArray(tileMap.counts), index: 2)
    argumentTable.setAddress(writeUniformArray(tileMap.indices), index: 3)

    let tg = MTLSize(width: 32, height: 16, depth: 1)
    let grid = MTLSize(width: velocityOut.width, height: velocityOut.height, depth: 1)
    encoder.dispatchThreads(threadsPerGrid: grid, threadsPerThreadgroup: tg)
  }

  func renderCompose(encoder: any MTL4ComputeCommandEncoder,
                     color: MTLTexture, heightWet: MTLTexture,
                     output: MTLTexture, params: AbExParams) {
    encoder.setComputePipelineState(composePipeline)
    argumentTable.setTexture(color.gpuResourceID, index: 0)
    argumentTable.setTexture(heightWet.gpuResourceID, index: 1)
    argumentTable.setTexture(output.gpuResourceID, index: 2)
    argumentTable.setAddress(writeUniform(params), index: 0)

    let tg = MTLSize(width: 32, height: 16, depth: 1)
    let grid = MTLSize(width: output.width, height: output.height, depth: 1)
    encoder.dispatchThreads(threadsPerGrid: grid, threadsPerThreadgroup: tg)
  }

  private struct PingPongTextures {
    let colorIn: MTLTexture, colorOut: MTLTexture
    let hwIn: MTLTexture, hwOut: MTLTexture
    let colorMid: MTLTexture, hwMid: MTLTexture
    let velocityIn: MTLTexture, velocityOut: MTLTexture
    let display: MTLTexture
  }

  private func currentPingPongTextures() -> PingPongTextures? {
    let readA = currentIsA
    guard let cIn   = readA ? colorA     : colorB,
          let cOut  = readA ? colorB     : colorA,
          let hwIn  = readA ? heightWetA : heightWetB,
          let hwOut = readA ? heightWetB : heightWetA,
          let vIn   = readA ? velocityA  : velocityB,
          let vOut  = readA ? velocityB  : velocityA,
          let cMid  = colorMid,
          let hwMid = heightWetMid,
          let disp  = displayTex else { return nil }
    return PingPongTextures(colorIn: cIn, colorOut: cOut,
                            hwIn: hwIn, hwOut: hwOut,
                            colorMid: cMid, hwMid: hwMid,
                            velocityIn: vIn, velocityOut: vOut,
                            display: disp)
  }

  private func buildFrameParams(smoothed: SIMD3<Float>, strokeCount: Int) -> AbExParams {
    let energy = (smoothed.x + smoothed.y + smoothed.z) / 3.0
    let baseDryRate: Float = isPlaying ? 0.0006 : 0.0008
    let dryRate: Float = baseDryRate + energy * 0.0002
    let bumpStrength: Float = 22.0

    let camPanX: Float = sin(cameraPhase * 0.13) * 0.015
                       + sin(cameraPhase * 0.29) * 0.006
    let camPanY: Float = cos(cameraPhase * 0.17) * 0.010
                       + sin(cameraPhase * 0.37) * 0.005
    let camZoom: Float = 1.0 + sin(cameraPhase * 0.20) * 0.020
                             + cos(cameraPhase * 0.43) * 0.008

    let cc = Self.canvasColor
    return AbExParams(
      audio: SIMD4(time, smoothed.x, smoothed.y, smoothed.z),
      canvas: SIMD4(cc.x, cc.y, cc.z, dryRate),
      config: SIMD4(dt, isFirstFrame ? 1.0 : 0.0, Float(strokeCount), bumpStrength),
      camera: SIMD4(camPanX, camPanY, camZoom, 0),
      atmosphere: SIMD4(atmosphereIntensity, songSeed, atmosphereHue, 0))
  }

  private struct SplitStrokes {
    let deposit: [AbExStroke]
    let smear: [AbExStroke]
  }

  private func splitStrokesByPhase(_ all: [AbExStroke]) -> SplitStrokes {
    let deposit = all.filter {
      let typeRaw = Int($0.sizeOpacity.w)
      return typeRaw != 0 && typeRaw != 4
    }
    let smear = all.filter {
      let typeRaw = Int($0.sizeOpacity.w)
      return typeRaw == 0 || typeRaw == 4
    }
    return SplitStrokes(deposit: deposit, smear: smear)
  }

  private func executePaintPipeline(encoder: any MTL4ComputeCommandEncoder,
                                    tex: PingPongTextures,
                                    smoothed: SIMD3<Float>,
                                    strokes: SplitStrokes) {
    let depositTileMap = buildTileMap(strokes: strokes.deposit)
    let smearTileMap   = buildTileMap(strokes: strokes.smear)

    let pass1Params = buildFrameParams(smoothed: smoothed,
                                        strokeCount: strokes.deposit.count)
    renderPaint(encoder: encoder,
                colorIn: tex.colorIn, colorOut: tex.colorMid,
                hwIn: tex.hwIn, hwOut: tex.hwMid,
                velocityIn: tex.velocityIn,
                params: pass1Params, strokes: strokes.deposit,
                tileMap: depositTileMap)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    let velocityParams = buildFrameParams(smoothed: smoothed,
                                           strokeCount: strokes.smear.count)
    renderVelocityDeposit(encoder: encoder,
                          velocityIn: tex.velocityIn,
                          velocityOut: tex.velocityOut,
                          heightWetIn: tex.hwMid,
                          params: velocityParams,
                          strokes: strokes.smear,
                          tileMap: smearTileMap)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    var pass2Params = buildFrameParams(smoothed: smoothed,
                                        strokeCount: strokes.smear.count)
    pass2Params.atmosphere = SIMD4(pass2Params.atmosphere.x,
                                    pass2Params.atmosphere.y,
                                    pass2Params.atmosphere.z,
                                    1.0)
    pass2Params.config = SIMD4(pass2Params.config.x, 0.0,
                                Float(strokes.smear.count),
                                pass2Params.config.w)
    renderPaint(encoder: encoder,
                colorIn: tex.colorMid, colorOut: tex.colorOut,
                hwIn: tex.hwMid, hwOut: tex.hwOut,
                velocityIn: tex.velocityOut,
                params: pass2Params, strokes: strokes.smear,
                tileMap: smearTileMap)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    renderCompose(encoder: encoder,
                  color: tex.colorOut, heightWet: tex.hwOut,
                  output: tex.display, params: pass2Params)
  }

  func encodeFrame(bass: Float,
                   mid: Float,
                   high: Float,
                   drawableWidth: Int,
                   drawableHeight: Int) -> MTLTexture? {
    drainPendingTextureReleases()
    let smoothed = processAudio(bass: bass, mid: mid, high: high)
    guard ensureCanvasTextures(displayWidth: drawableWidth, displayHeight: drawableHeight),
          let tex = currentPingPongTextures(),
          let encoder = beginFrame() else { return nil }

    let isClearing = pendingClearFrames > 0
    if isClearing {
      pendingClearFrames -= 1
      isFirstFrame = true
    }

    let allStrokes = isClearing ? [] : generateStrokes(audio: smoothed)
    let split = splitStrokesByPhase(allStrokes)

    if isPlaying {
      cameraPhase += dt * 0.30
    }

    executePaintPipeline(encoder: encoder, tex: tex, smoothed: smoothed, strokes: split)

    encoder.barrier(afterStages: .dispatch, beforeQueueStages: .fragment)
    encoder.endEncoding()

    isFirstFrame = false
    currentIsA.toggle()
    return tex.display
  }
}
