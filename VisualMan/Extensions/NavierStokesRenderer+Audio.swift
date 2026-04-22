//
//  NavierStokesRenderer+Audio.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import Metal
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

    forceSplats.removeAll(keepingCapacity: true)
    dyeSplats.removeAll(keepingCapacity: true)

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
    let gsF = Float(gridSize)
    var minX: Float = gsF
    var minY: Float = gsF
    var maxX: Float = 0
    var maxY: Float = 0
    let rMult: Float = sqrt(6.0)
    for sp in splats {
      let r = sp.radius * rMult
      minX = min(minX, sp.position.x - r)
      minY = min(minY, sp.position.y - r)
      maxX = max(maxX, sp.position.x + r)
      maxY = max(maxY, sp.position.y + r)
    }
    let ox = max(0, Int(floor(minX)))
    let oy = max(0, Int(floor(minY)))
    let ex = min(gridSize, Int(ceil(maxX)))
    let ey = min(gridSize, Int(ceil(maxY)))
    let regionW = ex - ox
    let regionH = ey - oy
    if regionW <= 0 || regionH <= 0 { return }

    encoder.setComputePipelineState(pipelines.splatBatch)
    argumentTable.setTexture(texture.gpuResourceID, index: 0)
    argumentTable.setAddress(writeUniformArray(splats), index: 0)
    let count = UInt32(splats.count)
    argumentTable.setAddress(writeUniform(count), index: 1)
    let origin = SIMD2<UInt32>(UInt32(ox), UInt32(oy))
    argumentTable.setAddress(writeUniform(origin), index: 2)
    dispatchGrid(encoder: encoder, width: regionW, height: regionH)
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
}
