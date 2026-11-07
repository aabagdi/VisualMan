//
//  LiquidLightRenderer+Rendering.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/12/26.
//

#if !targetEnvironment(simulator)
import Metal
import QuartzCore

extension LiquidLightRenderer {
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
        lastPressBass = 0
        smoothedSpeed = 0.25
        if gap > 2.0 {
          resumeFadeIn = 0
        }
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

    resumeSuppressionRemaining = max(0, resumeSuppressionRemaining - dt)
    let inResumeGrace = resumeSuppressionRemaining > 0

    let input = SIMD3<Float>(bass, mid, high)

    let fastAttackA = 1 - exp(-dt / 0.012)
    let fastDecayA  = 1 - exp(-dt / 0.12)
    var fastRate = SIMD3<Float>(repeating: fastDecayA)
    fastRate.replace(with: SIMD3<Float>(repeating: fastAttackA), where: input .> envelope)
    envelope += (input - envelope) * fastRate

    let slowA = 1 - exp(-dt / 0.35)
    slowEnvelope += (input - slowEnvelope) * slowA

    let audioEnergy = slowEnvelope.sum() / 3.0
    let targetSpeed = 0.09 + audioEnergy * 0.22
    let speedA = 1 - exp(-dt / (targetSpeed > smoothedSpeed ? 0.3 : 0.5))
    smoothedSpeed += (targetSpeed - smoothedSpeed) * speedA
    time += dt * smoothedSpeed

    tiltPhase += dt * (0.08 + audioEnergy * 0.12)
    tiltAxis += dt * 0.025

    detectAndEmitDrop(bass: bass, inResumeGrace: inResumeGrace)

    if resumeFadeIn < 1 {
      resumeFadeIn = min(1, resumeFadeIn + dt / Self.resumeFadeDuration)
    }
    let u = resumeFadeIn
    let fade = u * u * (3 - 2 * u)
    return envelope * fade
  }

  private var simSize: SIMD2<Float> {
    SIMD2<Float>(Float(simWidth), Float(simHeight))
  }

  private func dispatch(_ encoder: any MTL4ComputeCommandEncoder, width: Int, height: Int) {
    let tg = MTLSize(width: 16, height: 16, depth: 1)
    let grid = MTLSize(width: width, height: height, depth: 1)
    encoder.dispatchThreads(threadsPerGrid: grid, threadsPerThreadgroup: tg)
  }

  func seedPhase(encoder: any MTL4ComputeCommandEncoder, phaseOut: MTLTexture) {
    encoder.setComputePipelineState(seedPipeline)
    argumentTable.setTexture(phaseOut.gpuResourceID, index: 0)
    let params = LiquidSeedParams(simSize: simSize, eps: Self.interfaceEps, threshold: 0.5)
    argumentTable.setAddress(writeUniform(params), index: 0)
    dispatch(encoder, width: phaseOut.width, height: phaseOut.height)
  }

  func resamplePhase(encoder: any MTL4ComputeCommandEncoder,
                     phaseIn: MTLTexture,
                     phaseOut: MTLTexture) {
    encoder.setComputePipelineState(resamplePipeline)
    argumentTable.setTexture(phaseIn.gpuResourceID, index: 0)
    argumentTable.setTexture(phaseOut.gpuResourceID, index: 1)
    dispatch(encoder, width: phaseOut.width, height: phaseOut.height)
  }

  func advectPhase(encoder: any MTL4ComputeCommandEncoder,
                   phaseIn: MTLTexture,
                   phaseOut: MTLTexture,
                   audio: SIMD3<Float>) {
    encoder.setComputePipelineState(advectPipeline)
    argumentTable.setTexture(phaseIn.gpuResourceID, index: 0)
    argumentTable.setTexture(phaseOut.gpuResourceID, index: 1)

    let energy = slowEnvelope.sum() / 3.0
    let axis = SIMD2<Float>(cos(tiltAxis), sin(tiltAxis))
    let lean = SIMD2<Float>(cos(tiltAxis * 0.31 + 1.2), sin(tiltAxis * 0.31 + 1.2))
    let rock = sin(tiltPhase)
    let tilt = axis * rock * (0.18 + energy * 0.4) + lean * 0.04

    let pressDelta = audio.x - lastPressBass
    lastPressBass = audio.x
    let press = max(-5, min(5, pressDelta * 14))

    let params = LiquidAdvectParams(
      simSize: simSize,
      tilt: tilt,
      frames: dt * 60,
      time: time,
      swirl: 0.04 + audio.y * 0.12,
      press: press,
      eps: Self.interfaceEps,
      drops: LiquidLightDrops(d0: drops[0], d1: drops[1], d2: drops[2], d3: drops[3]),
      dropState: dropStateUniforms()
    )
    argumentTable.setAddress(writeUniform(params), index: 0)
    dispatch(encoder, width: phaseOut.width, height: phaseOut.height)
  }

  func reduceMassMultiplier(encoder: any MTL4ComputeCommandEncoder, phase: MTLTexture) {
    let tile = Self.reduceTileSize
    let tilesX = (phase.width + tile - 1) / tile
    let tilesY = (phase.height + tile - 1) / tile
    let tileCount = tilesX * tilesY
    guard tileCount <= Self.maxReduceTiles else {
      assertionFailure("Liquid Light sim too large for the reduction scratch buffer")
      return
    }

    encoder.setComputePipelineState(reduceTilesPipeline)
    argumentTable.setTexture(phase.gpuResourceID, index: 0)
    argumentTable.setAddress(reduceTilesBuffer.gpuAddress, index: 1)
    encoder.dispatchThreadgroups(threadgroupsPerGrid: MTLSize(width: tilesX, height: tilesY, depth: 1),
                                 threadsPerThreadgroup: MTLSize(width: tile, height: tile, depth: 1))
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    encoder.setComputePipelineState(reduceFinalPipeline)
    let params = LiquidReduceParams(tileCount: UInt32(tileCount),
                                    invCellCount: 1 / Float(phase.width * phase.height))
    argumentTable.setAddress(writeUniform(params), index: 0)
    argumentTable.setAddress(lambdaBuffer.gpuAddress, index: 2)
    encoder.dispatchThreadgroups(threadgroupsPerGrid: MTLSize(width: 1, height: 1, depth: 1),
                                 threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
  }

  func relaxPhase(encoder: any MTL4ComputeCommandEncoder,
                  phaseIn: MTLTexture,
                  phaseOut: MTLTexture) {
    encoder.setComputePipelineState(relaxPipeline)
    argumentTable.setTexture(phaseIn.gpuResourceID, index: 0)
    argumentTable.setTexture(phaseOut.gpuResourceID, index: 1)
    let params = LiquidRelaxParams(dt: Self.relaxStep, mobility: Self.mobility,
                                   eps2: Self.interfaceEps * Self.interfaceEps,
                                   acMobility: Self.acMobility)
    argumentTable.setAddress(writeUniform(params), index: 0)
    argumentTable.setAddress(lambdaBuffer.gpuAddress, index: 1)
    dispatch(encoder, width: phaseOut.width, height: phaseOut.height)
  }

  func renderLiquidLight(encoder: any MTL4ComputeCommandEncoder,
                         output: MTLTexture,
                         phase: MTLTexture,
                         audio: SIMD3<Float>) {
    encoder.setComputePipelineState(renderPipeline)
    argumentTable.setTexture(output.gpuResourceID, index: 0)
    argumentTable.setTexture(phase.gpuResourceID, index: 1)

    let params = LiquidLightParams(
      time: time, bass: audio.x, mid: audio.y, high: audio.z,
      simSize: simSize, eps: Self.interfaceEps,
      apertureRadius: Self.apertureRadius,
      plate: currentPlate(),
      ripples: rippleUniforms()
    )
    argumentTable.setAddress(writeUniform(params), index: 0)
    dispatch(encoder, width: output.width, height: output.height)
  }

  static let halogen = SIMD4<Float>(1.0, 0.91, 0.70, 0)

  static let plates: [LiquidLightPlate] = [
    LiquidLightPlate(dyeA: SIMD4(0.93, 0.07, 0.09, 0), dyeB: SIMD4(1.0, 0.84, 0.12, 0),
                     dyeC: SIMD4(0.12, 0.34, 0.95, 0), dyeD: SIMD4(0.92, 0.10, 0.55, 0),
                     water: SIMD4(0.40, 0.72, 1.0, 0.9), lamp: halogen),
    LiquidLightPlate(dyeA: SIMD4(0.92, 0.09, 0.55, 0), dyeB: SIMD4(1.0, 0.50, 0.08, 0),
                     dyeC: SIMD4(0.52, 0.14, 0.93, 0), dyeD: SIMD4(0.10, 0.78, 0.93, 0),
                     water: SIMD4(0.12, 0.18, 0.80, 0.9), lamp: halogen),
    LiquidLightPlate(dyeA: SIMD4(1.0, 0.80, 0.10, 0), dyeB: SIMD4(0.14, 0.78, 0.18, 0),
                     dyeC: SIMD4(0.93, 0.08, 0.08, 0), dyeD: SIMD4(1.0, 0.46, 0.08, 0),
                     water: SIMD4(0.90, 0.14, 0.08, 0.92), lamp: halogen),
    LiquidLightPlate(dyeA: SIMD4(0.10, 0.78, 0.93, 0), dyeB: SIMD4(0.95, 0.10, 0.50, 0),
                     dyeC: SIMD4(1.0, 0.90, 0.12, 0), dyeD: SIMD4(0.20, 0.85, 0.25, 0),
                     water: SIMD4(0.50, 0.28, 0.92, 0.9), lamp: halogen),
    LiquidLightPlate(dyeA: SIMD4(0.93, 0.07, 0.10, 0), dyeB: SIMD4(0.55, 0.14, 0.90, 0),
                     dyeC: SIMD4(1.0, 0.46, 0.08, 0), dyeD: SIMD4(0.10, 0.70, 0.64, 0),
                     water: SIMD4(0.68, 0.48, 1.0, 0.9), lamp: halogen),
    LiquidLightPlate(dyeA: SIMD4(1.0, 0.50, 0.08, 0), dyeB: SIMD4(0.96, 0.14, 0.45, 0),
                     dyeC: SIMD4(0.10, 0.70, 0.64, 0), dyeD: SIMD4(1.0, 0.86, 0.15, 0),
                     water: SIMD4(0.32, 0.08, 0.62, 0.9), lamp: halogen),
  ]

  static let plateDuration: Float = 90
  static let plateCrossfade: Float = 14
  static let hueDriftRate: Float = 0.035

  func currentPlate() -> LiquidLightPlate {
    let plates = Self.plates
    let cycle = wallClock / Self.plateDuration
    let index = Int(cycle.rounded(.down)) % plates.count
    let next = (index + 1) % plates.count
    let frac = cycle - cycle.rounded(.down)
    let fadeStart = 1 - Self.plateCrossfade / Self.plateDuration
    let u = max(0, min(1, (frac - fadeStart) / (1 - fadeStart)))
    let blend = u * u * (3 - 2 * u)

    let a = plates[index], b = plates[next]
    let hue = wallClock * Self.hueDriftRate
    func mix(_ x: SIMD4<Float>, _ y: SIMD4<Float>) -> SIMD4<Float> {
      Self.rotateHue(x + (y - x) * blend, by: hue)
    }
    return LiquidLightPlate(dyeA: mix(a.dyeA, b.dyeA), dyeB: mix(a.dyeB, b.dyeB),
                            dyeC: mix(a.dyeC, b.dyeC), dyeD: mix(a.dyeD, b.dyeD),
                            water: mix(a.water, b.water),
                            lamp: a.lamp + (b.lamp - a.lamp) * blend)
  }

  static func rotateHue(_ c: SIMD4<Float>, by angle: Float) -> SIMD4<Float> {
    let y = 0.299 * c.x + 0.587 * c.y + 0.114 * c.z
    let i = 0.596 * c.x - 0.274 * c.y - 0.322 * c.z
    let q = 0.211 * c.x - 0.523 * c.y + 0.312 * c.z
    let cs = cos(angle), sn = sin(angle)
    let i2 = i * cs - q * sn
    let q2 = i * sn + q * cs
    let r = y + 0.956 * i2 + 0.621 * q2
    let g = y - 0.272 * i2 - 0.647 * q2
    let b = y - 1.106 * i2 + 1.703 * q2
    return SIMD4<Float>(max(0.02, min(1, r)), max(0.02, min(1, g)), max(0.02, min(1, b)), c.w)
  }

  func renderFeedback(encoder: any MTL4ComputeCommandEncoder,
                      render: MTLTexture,
                      historyIn: MTLTexture,
                      historyOut: MTLTexture,
                      audio: SIMD3<Float>,
                      historyValid: Bool) {
    encoder.setComputePipelineState(feedbackPipeline)

    argumentTable.setTexture(render.gpuResourceID, index: 0)
    argumentTable.setTexture(historyIn.gpuResourceID, index: 1)
    argumentTable.setTexture(historyOut.gpuResourceID, index: 2)

    let params = FeedbackParams(dt: dt, time: time, bass: audio.x,
                                historyValid: historyValid ? 1 : 0)
    argumentTable.setAddress(writeUniform(params), index: 0)
    dispatch(encoder, width: historyOut.width, height: historyOut.height)
  }

  func renderBlur(encoder: any MTL4ComputeCommandEncoder,
                  input: MTLTexture,
                  output: MTLTexture,
                  audio: SIMD3<Float>) {
    encoder.setComputePipelineState(blurPipeline)

    argumentTable.setTexture(input.gpuResourceID, index: 0)
    argumentTable.setTexture(output.gpuResourceID, index: 1)

    let blurParams = BlurParams(
      innerRadius: 0.55 + audio.y * 0.05,
      outerRadius: 1.2,
      maxBlurRadius: 6.0 + audio.y * 2.0,
      bass: audio.x,
      mid: audio.y,
      bloomRadius: 18.0,
      bloomStrength: 0.28 + audio.x * 0.1
    )
    argumentTable.setAddress(writeUniform(blurParams), index: 0)
    dispatch(encoder, width: output.width, height: output.height)
  }
}

#endif
