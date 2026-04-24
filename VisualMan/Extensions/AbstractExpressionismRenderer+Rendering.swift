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

    if resumeFadeIn < 1 {
      resumeFadeIn = min(1, resumeFadeIn + dt / Self.resumeFadeDuration)
    }
    let u = resumeFadeIn
    let fade = u * u * (3 - 2 * u)
    return envelope * fade
  }

  func renderPaint(encoder: any MTL4ComputeCommandEncoder,
                   colorBackIn: MTLTexture, colorBackOut: MTLTexture,
                   colorMidIn: MTLTexture, colorMidOut: MTLTexture,
                   colorFrontIn: MTLTexture, colorFrontOut: MTLTexture,
                   heightBackIn: MTLTexture, heightBackOut: MTLTexture,
                   heightMFIn: MTLTexture, heightMFOut: MTLTexture,
                   params: AbExParams, strokes: [AbExStroke]) {
    encoder.setComputePipelineState(paintPipeline)
    argumentTable.setTexture(colorBackIn.gpuResourceID, index: 0)
    argumentTable.setTexture(colorBackOut.gpuResourceID, index: 1)
    argumentTable.setTexture(colorMidIn.gpuResourceID, index: 2)
    argumentTable.setTexture(colorMidOut.gpuResourceID, index: 3)
    argumentTable.setTexture(colorFrontIn.gpuResourceID, index: 4)
    argumentTable.setTexture(colorFrontOut.gpuResourceID, index: 5)
    argumentTable.setTexture(heightBackIn.gpuResourceID, index: 6)
    argumentTable.setTexture(heightBackOut.gpuResourceID, index: 7)
    argumentTable.setTexture(heightMFIn.gpuResourceID, index: 8)
    argumentTable.setTexture(heightMFOut.gpuResourceID, index: 9)
    argumentTable.setAddress(writeUniform(params), index: 0)

    if strokes.isEmpty {
      let empty = AbExStroke(posAngle: .zero, sizeOpacity: .zero, color: .zero)
      argumentTable.setAddress(writeUniform(empty), index: 1)
    } else {
      argumentTable.setAddress(writeUniformArray(strokes), index: 1)
    }

    let tg = MTLSize(width: 16, height: 16, depth: 1)
    let grid = MTLSize(width: colorBackOut.width, height: colorBackOut.height, depth: 1)
    encoder.dispatchThreads(threadsPerGrid: grid, threadsPerThreadgroup: tg)
  }

  func renderCompose(encoder: any MTL4ComputeCommandEncoder,
                     colorBack: MTLTexture, colorMid: MTLTexture, colorFront: MTLTexture,
                     heightBack: MTLTexture, heightMF: MTLTexture,
                     output: MTLTexture, params: AbExParams) {
    encoder.setComputePipelineState(composePipeline)
    argumentTable.setTexture(colorBack.gpuResourceID, index: 0)
    argumentTable.setTexture(colorMid.gpuResourceID, index: 1)
    argumentTable.setTexture(colorFront.gpuResourceID, index: 2)
    argumentTable.setTexture(heightBack.gpuResourceID, index: 3)
    argumentTable.setTexture(heightMF.gpuResourceID, index: 4)
    argumentTable.setTexture(output.gpuResourceID, index: 5)
    argumentTable.setAddress(writeUniform(params), index: 0)

    let tg = MTLSize(width: 16, height: 16, depth: 1)
    let grid = MTLSize(width: output.width, height: output.height, depth: 1)
    encoder.dispatchThreads(threadsPerGrid: grid, threadsPerThreadgroup: tg)
  }

  private struct PingPongTextures {
    let backIn: MTLTexture, backOut: MTLTexture
    let midIn: MTLTexture, midOut: MTLTexture
    let frontIn: MTLTexture, frontOut: MTLTexture
    let hbIn: MTLTexture, hbOut: MTLTexture
    let hmfIn: MTLTexture, hmfOut: MTLTexture
    let display: MTLTexture
  }

  private func currentPingPongTextures() -> PingPongTextures? {
    let readA = currentIsA
    guard let backIn    = readA ? colorBackA   : colorBackB,
          let backOut   = readA ? colorBackB   : colorBackA,
          let midIn     = readA ? colorMidA    : colorMidB,
          let midOut    = readA ? colorMidB    : colorMidA,
          let frontIn   = readA ? colorFrontA  : colorFrontB,
          let frontOut  = readA ? colorFrontB  : colorFrontA,
          let hbIn      = readA ? heightBackA  : heightBackB,
          let hbOut     = readA ? heightBackB  : heightBackA,
          let hmfIn     = readA ? heightMFA    : heightMFB,
          let hmfOut    = readA ? heightMFB    : heightMFA,
          let disp      = displayTex else { return nil }
    return PingPongTextures(backIn: backIn, backOut: backOut,
                            midIn: midIn, midOut: midOut,
                            frontIn: frontIn, frontOut: frontOut,
                            hbIn: hbIn, hbOut: hbOut,
                            hmfIn: hmfIn, hmfOut: hmfOut,
                            display: disp)
  }

  private func buildFrameParams(smoothed: SIMD3<Float>, strokeCount: Int) -> AbExParams {
    let energy = (smoothed.x + smoothed.y + smoothed.z) / 3.0
    let dryRate: Float = 0.0003 + energy * 0.0002
    let bumpStrength: Float = 13.0

    cameraPhase += dt * 0.30
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
      config: SIMD4(0, isFirstFrame ? 1.0 : 0.0, Float(strokeCount), bumpStrength),
      camera: SIMD4(camPanX, camPanY, camZoom, 0))
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

    let strokes = generateStrokes(audio: smoothed)
    let params = buildFrameParams(smoothed: smoothed, strokeCount: strokes.count)

    renderPaint(encoder: encoder,
                colorBackIn: tex.backIn, colorBackOut: tex.backOut,
                colorMidIn: tex.midIn, colorMidOut: tex.midOut,
                colorFrontIn: tex.frontIn, colorFrontOut: tex.frontOut,
                heightBackIn: tex.hbIn, heightBackOut: tex.hbOut,
                heightMFIn: tex.hmfIn, heightMFOut: tex.hmfOut,
                params: params, strokes: strokes)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    renderCompose(encoder: encoder,
                  colorBack: tex.backOut, colorMid: tex.midOut, colorFront: tex.frontOut,
                  heightBack: tex.hbOut, heightMF: tex.hmfOut,
                  output: tex.display, params: params)

    encoder.barrier(afterStages: .dispatch, beforeQueueStages: .fragment)
    encoder.endEncoding()

    isFirstFrame = false
    currentIsA.toggle()
    return tex.display
  }
}
