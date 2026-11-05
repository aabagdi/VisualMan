//
//  AbstractExpressionismRenderer+Rendering.swift
//  VisualMan
//
//  Created by on 4/23/26.
//

#if !targetEnvironment(simulator)
import Metal
import QuartzCore

extension AbstractExpressionismRenderer {
  func renderPaint(encoder: any MTL4ComputeCommandEncoder,
                   colorIn: MTLTexture, colorOut: MTLTexture,
                   hwIn: MTLTexture, hwOut: MTLTexture,
                   velocityIn: MTLTexture,
                   dryColorIn: MTLTexture, dryColorOut: MTLTexture,
                   substrateIn: MTLTexture, substrateOut: MTLTexture,
                   params: AbExParams, strokes: [AbExStroke],
                   tileMap: TileMap,
                   region: CanvasRegion) {
    encoder.setComputePipelineState(paintPipeline)
    argumentTable.setTexture(colorIn.gpuResourceID, index: 0)
    argumentTable.setTexture(colorOut.gpuResourceID, index: 1)
    argumentTable.setTexture(hwIn.gpuResourceID, index: 2)
    argumentTable.setTexture(hwOut.gpuResourceID, index: 3)
    argumentTable.setTexture(velocityIn.gpuResourceID, index: 4)
    argumentTable.setTexture(dryColorIn.gpuResourceID, index: 5)
    argumentTable.setTexture(dryColorOut.gpuResourceID, index: 6)
    argumentTable.setTexture(substrateIn.gpuResourceID, index: 7)
    argumentTable.setTexture(substrateOut.gpuResourceID, index: 8)
    if let lut = mixboxLUT {
      argumentTable.setTexture(lut.gpuResourceID, index: 9)
    }
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
    argumentTable.setAddress(writeUniform(region.origin), index: 4)

    dispatch(encoder: encoder, pipeline: paintPipeline,
             width: region.width, height: region.height)
  }

  func renderVelocityDeposit(encoder: any MTL4ComputeCommandEncoder,
                             velocityIn: MTLTexture, velocityOut: MTLTexture,
                             heightWetIn: MTLTexture,
                             params: AbExParams, strokes: [AbExStroke],
                             tileMap: TileMap,
                             region: CanvasRegion) {
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
    let half = region.halved
    argumentTable.setAddress(writeUniform(half.origin), index: 4)

    dispatch(encoder: encoder, pipeline: velocityPipeline,
             width: half.width, height: half.height)
  }

  func renderResample(encoder: any MTL4ComputeCommandEncoder,
                      colorSrc: MTLTexture, colorDst: MTLTexture,
                      hwSrc: MTLTexture, hwDst: MTLTexture,
                      drySrc: MTLTexture, dryDst: MTLTexture,
                      subSrc: MTLTexture, subDst: MTLTexture,
                      velDst: MTLTexture) {
    encoder.setComputePipelineState(resamplePipeline)
    argumentTable.setTexture(colorSrc.gpuResourceID, index: 0)
    argumentTable.setTexture(colorDst.gpuResourceID, index: 1)
    argumentTable.setTexture(hwSrc.gpuResourceID, index: 2)
    argumentTable.setTexture(hwDst.gpuResourceID, index: 3)
    argumentTable.setTexture(drySrc.gpuResourceID, index: 4)
    argumentTable.setTexture(dryDst.gpuResourceID, index: 5)
    argumentTable.setTexture(subSrc.gpuResourceID, index: 6)
    argumentTable.setTexture(subDst.gpuResourceID, index: 7)
    argumentTable.setTexture(velDst.gpuResourceID, index: 8)

    dispatch(encoder: encoder, pipeline: resamplePipeline,
             width: colorDst.width, height: colorDst.height)
  }

  func renderCompose(encoder: any MTL4ComputeCommandEncoder,
                     color: MTLTexture, heightWet: MTLTexture,
                     dryColor: MTLTexture,
                     substrate: MTLTexture,
                     output: MTLTexture, params: AbExParams) {
    encoder.setComputePipelineState(composePipeline)
    argumentTable.setTexture(color.gpuResourceID, index: 0)
    argumentTable.setTexture(heightWet.gpuResourceID, index: 1)
    argumentTable.setTexture(output.gpuResourceID, index: 2)
    argumentTable.setTexture(dryColor.gpuResourceID, index: 3)
    argumentTable.setTexture(substrate.gpuResourceID, index: 4)
    if let lut = mixboxLUT {
      argumentTable.setTexture(lut.gpuResourceID, index: 5)
    }
    if let cracks = crackTexture {
      argumentTable.setTexture(cracks.gpuResourceID, index: 6)
    }
    argumentTable.setTexture((pigmentTexture ?? color).gpuResourceID, index: 7)
    argumentTable.setTexture((materialTexture ?? color).gpuResourceID, index: 8)
    argumentTable.setAddress(writeUniform(params), index: 0)

    dispatch(encoder: encoder, pipeline: composePipeline,
             width: output.width, height: output.height)
  }

  struct PingPongTextures {
    let colorIn: MTLTexture, colorOut: MTLTexture
    let hwIn: MTLTexture, hwOut: MTLTexture
    let colorMid: MTLTexture, hwMid: MTLTexture
    let velocityIn: MTLTexture, velocityOut: MTLTexture
    let dryColorIn: MTLTexture, dryColorOut: MTLTexture, dryColorMid: MTLTexture
    let substrateIn: MTLTexture, substrateOut: MTLTexture
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
          let dcIn  = readA ? dryColorA  : dryColorB,
          let dcOut = readA ? dryColorB  : dryColorA,
          let sIn   = readA ? substrateA : substrateB,
          let sOut  = readA ? substrateB : substrateA,
          let cMid  = colorMid,
          let hwMid = heightWetMid,
          let dcMid = dryColorMid,
          displayTextures.count == 2 else { return nil }
    let disp = displayTextures[displayIsA ? 0 : 1]
    return PingPongTextures(colorIn: cIn, colorOut: cOut,
                            hwIn: hwIn, hwOut: hwOut,
                            colorMid: cMid, hwMid: hwMid,
                            velocityIn: vIn, velocityOut: vOut,
                            dryColorIn: dcIn, dryColorOut: dcOut,
                            dryColorMid: dcMid,
                            substrateIn: sIn, substrateOut: sOut,
                            display: disp)
  }

  func buildFrameParams(smoothed: SIMD3<Float>, strokeCount: Int) -> AbExParams {
    let energy = (smoothed.x + smoothed.y + smoothed.z) / 3.0
    let baseDryRate: Float = isPlaying ? 0.0006 : 0.0008
    let dryRate: Float = (baseDryRate + energy * 0.0002) * paintDt * 60
                       * paintTestDryMultiplier
    let bumpStrength: Float = 22.0

    let camPanX: Float = sin(cameraPhase * 0.13) * 0.015
                       + sin(cameraPhase * 0.29) * 0.006
    let camPanY: Float = cos(cameraPhase * 0.17) * 0.010
                       + sin(cameraPhase * 0.37) * 0.005
    let camZoom: Float = 1.0 + sin(cameraPhase * 0.20) * 0.020
                             + cos(cameraPhase * 0.43) * 0.008

    let cc = Self.canvasColor
    return AbExParams(
      canvas: SIMD4(cc.x, cc.y, cc.z, dryRate),
      config: SIMD4(paintDt, isFirstFrame ? 1.0 : 0.0, Float(strokeCount), bumpStrength),
      camera: SIMD4(camPanX, camPanY, camZoom, Float(Self.paintTestDebugMode)),
      atmosphere: SIMD4(time, songSeed, 0, 0))
  }

  struct SplitStrokes {
    let deposit: [AbExStroke]
    let smear: [AbExStroke]
    var isEmpty: Bool { deposit.isEmpty && smear.isEmpty }
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

  private func executeSmearAndCompose(encoder: any MTL4ComputeCommandEncoder,
                                      tex: PingPongTextures,
                                      smoothed: SIMD3<Float>,
                                      smearStrokes: [AbExStroke],
                                      smearTileMap: TileMap,
                                      runSmearPass: Bool,
                                      region: CanvasRegion) {
    var pass2Params = buildFrameParams(smoothed: smoothed,
                                        strokeCount: smearStrokes.count)
    pass2Params.atmosphere = SIMD4(pass2Params.atmosphere.x,
                                    pass2Params.atmosphere.y,
                                    pass2Params.atmosphere.z,
                                    1.0)
    pass2Params.config = SIMD4(pass2Params.config.x, 0.0,
                                Float(smearStrokes.count),
                                pass2Params.config.w)
    
    if runSmearPass, let smearRegion = smearPassRegion(within: region) {
      copyForSmearPass(encoder: encoder, tex: tex, region: smearRegion)
      renderPaint(encoder: encoder,
                  colorIn: tex.colorMid, colorOut: tex.colorOut,
                  hwIn: tex.hwMid, hwOut: tex.hwOut,
                  velocityIn: tex.velocityOut,
                  dryColorIn: tex.dryColorMid, dryColorOut: tex.dryColorOut,
                  substrateIn: tex.substrateOut, substrateOut: tex.substrateOut,
                  params: pass2Params, strokes: smearStrokes,
                  tileMap: smearTileMap,
                  region: smearRegion)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
    gpuMark(encoder, .afterSmear)

    renderPigment(encoder: encoder, wet: tex.colorOut, dry: tex.dryColorOut,
                  heightWet: tex.hwOut, substrate: tex.substrateOut,
                  params: pass2Params, regions: pigmentRegionsThisFrame)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    gpuMark(encoder, .afterPigment)

    renderCompose(encoder: encoder,
                  color: tex.colorOut, heightWet: tex.hwOut,
                  dryColor: tex.dryColorOut,
                  substrate: tex.substrateOut,
                  output: tex.display, params: pass2Params)
    gpuMark(encoder, .afterCompose)
  }

  private func executePaintPipeline(encoder: any MTL4ComputeCommandEncoder,
                                    tex: PingPongTextures,
                                    smoothed: SIMD3<Float>,
                                    strokes: SplitStrokes,
                                    region: CanvasRegion) {
    pigmentRegionsThisFrame = pigmentRegions(paintRegion: region,
                                             strokes: strokes.deposit + strokes.smear)
    let depositTileMap = buildTileMap(strokes: strokes.deposit)
    let smearTileMap   = buildTileMap(strokes: strokes.smear)

    if strokes.smear.isEmpty {
      framesSinceSmear += 1
    } else {
      framesSinceSmear = 0
    }
    let velocityFieldQuiet = framesSinceSmear > 12
    let runSmearPass = !strokes.smear.isEmpty || !velocityFieldQuiet
    recordSmearBounds(strokes.smear)

    let pass1Color   = tex.colorOut
    let pass1HW      = tex.hwOut
    let pass1DryCol  = tex.dryColorOut

    let pass1Params = buildFrameParams(smoothed: smoothed,
                                        strokeCount: strokes.deposit.count)
    gpuMark(encoder, .frameStart)
    renderPaint(encoder: encoder,
                colorIn: tex.colorIn, colorOut: pass1Color,
                hwIn: tex.hwIn, hwOut: pass1HW,
                velocityIn: tex.velocityIn,
                dryColorIn: tex.dryColorIn, dryColorOut: pass1DryCol,
                substrateIn: tex.substrateIn, substrateOut: tex.substrateOut,
                params: pass1Params, strokes: strokes.deposit,
                tileMap: depositTileMap,
                region: region)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    gpuMark(encoder, .afterPaint)

    let velocityParams = buildFrameParams(smoothed: smoothed,
                                           strokeCount: strokes.smear.count)
    renderVelocityDeposit(encoder: encoder,
                          velocityIn: tex.velocityIn,
                          velocityOut: tex.velocityOut,
                          heightWetIn: pass1HW,
                          params: velocityParams,
                          strokes: strokes.smear,
                          tileMap: smearTileMap,
                          region: region)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    gpuMark(encoder, .afterVelocity)

    executeSmearAndCompose(encoder: encoder, tex: tex, smoothed: smoothed,
                            smearStrokes: strokes.smear,
                            smearTileMap: smearTileMap,
                            runSmearPass: runSmearPass,
                            region: region)
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
    gpuTiming?.beginFrame(frameNumber: frameNumber, skippedPaint: false)

    runPendingResample(encoder: encoder, tex: tex)

    let isClearing = pendingClearFrames > 0
    if isClearing {
      pendingClearFrames -= 1
      isFirstFrame = true
    }
    if isFirstFrame {
      fullCanvasFramesRemaining = 2
    }
    let paintFullCanvas = fullCanvasFramesRemaining > 0
    if paintFullCanvas { pigmentFullRefreshFrames = max(pigmentFullRefreshFrames, 3) }
    fullCanvasFramesRemaining = max(0, fullCanvasFramesRemaining - 1)

    let allStrokes = isClearing ? [] : generateStrokes(audio: smoothed)
    let (region, paintedStrokes) = paintRegion(full: paintFullCanvas,
                                               strokes: allStrokes)
    let split = splitStrokesByPhase(paintedStrokes)

    if isPlaying {
      cameraPhase += dt * 0.30
    }

    let skipPaint = shouldSkipPaint(split: split, fullCanvas: paintFullCanvas,
                                    isClearing: isClearing)
    if skipPaint {
      encodeComposeOnly(encoder: encoder, tex: tex,
                        params: buildFrameParams(smoothed: smoothed, strokeCount: 0))
    } else {
      paintDt = dt + skippedPaintDt
      skippedPaintDt = 0
      executePaintPipeline(encoder: encoder, tex: tex, smoothed: smoothed,
                           strokes: split, region: region)
    }
    lastFrameSkippedPaint = skipPaint

    encoder.barrier(afterStages: .dispatch, beforeQueueStages: .fragment)
    encoder.endEncoding()

    isFirstFrame = false
    if !skipPaint { currentIsA.toggle() }
    displayIsA.toggle()
    return tex.display
  }

  func dispatch(encoder: any MTL4ComputeCommandEncoder,
                pipeline: MTLComputePipelineState,
                width: Int, height: Int) {
    let tgWidth = min(32, pipeline.maxTotalThreadsPerThreadgroup)
    let tgHeight = max(1, min(16, pipeline.maxTotalThreadsPerThreadgroup / tgWidth))
    encoder.dispatchThreads(threadsPerGrid: MTLSize(width: width, height: height, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: tgWidth, height: tgHeight, depth: 1))
  }
}

#endif
