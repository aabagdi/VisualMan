//
//  AbstractExpressionismRenderer+StrokeAnimation.swift
//  VisualMan
//
//  Created by on 4/29/26.
//

#if !targetEnvironment(simulator)
import Metal

extension AbstractExpressionismRenderer {
  func advanceAnimatingStrokes() {
    animatingStrokes.removeAll { $0.previousElapsed >= $0.duration }
    for i in animatingStrokes.indices {
      animatingStrokes[i].previousElapsed = animatingStrokes[i].elapsed
      animatingStrokes[i].elapsed = min(animatingStrokes[i].elapsed + dt,
                                        animatingStrokes[i].duration)
    }
  }

  func enqueueAnimatingStrokes(_ fresh: [AbExStroke]) -> [AbExStroke] {
    var overflow = [AbExStroke]()
    for s in fresh {
      guard animatingStrokes.count < Self.maxAnimatingStrokes else {
        overflow.append(s)
        continue
      }
      let typeRaw = Int(s.sizeOpacity.w)
      let duration: Float
      
      switch typeRaw {
      case 4:  duration = Self.knifeAnimationSeconds
      case 1:  duration = Self.washAnimationSeconds
      case 5:  duration = Self.scumbleAnimationSeconds
      default: duration = Self.gesturalAnimationSeconds
      }
      
      animatingStrokes.append(AnimatingStroke(
        stroke: s, previousElapsed: 0, elapsed: min(dt, duration), duration: duration))
    }
    return overflow
  }

  private func generateGesturalCandidates(energy: Float,
                                          focus: SIMD2<Float>,
                                          spread: Float) -> [AbExStroke] {
    var candidates = [AbExStroke]()
    if energy > 0.05
        && (wallClock - lastGesturalTime) > 1.8
        && candidates.count < Self.maxStrokesPerFrame
        && nextSeed() < perFrameChance(0.16) {
      appendGesturalStroke(to: &candidates, energy: energy, focus: focus, spread: spread)
    }
    if energy > 0.25
        && (wallClock - lastGesturalTime) > 1.1
        && candidates.count < Self.maxStrokesPerFrame
        && nextSeed() < perFrameChance(0.035) {
      appendGesturalStroke(to: &candidates, energy: energy, focus: focus, spread: spread)
    }
    return candidates
  }

  func generateStrokes(audio: SIMD3<Float>) -> [AbExStroke] {
    if Self.paintTestEnabled {
      return generatePaintTestStrokes()
    }
    decayFlow()
    decayDensity()
    advanceAnimatingStrokes()

    var strokes = [AbExStroke]()
    if !isPlaying || resumeSuppressionRemaining > 0 {
      return emitAnimatedStrokes(into: strokes)
    }

    let bass = audio.x, mid = audio.y, high = audio.z
    let energy = (bass + mid + high) / 3.0
    let focus = compositionFocus()
    let spread: Float = 0.85 + energy * 0.5

    var freshSmearStrokes = [AbExStroke]()
    let preGestural = generateGesturalCandidates(energy: energy, focus: focus, spread: spread)
    for s in preGestural {
      let typeRaw = Int(s.sizeOpacity.w)
      if typeRaw == 0 {
        freshSmearStrokes.append(s)
      } else {
        strokes.append(s)
      }
    }

    collectAppended(after: strokes, into: &freshSmearStrokes) {
      appendWash(to: &$0, mid: mid, focus: focus)
      appendAmbientWash(to: &$0, energy: energy, focus: focus)
    }

    appendRogueStroke(to: &strokes, energy: energy)

    collectAppended(after: strokes, into: &freshSmearStrokes) {
      appendScumble(to: &$0, mid: mid, energy: energy, focus: focus)
    }

    appendSplatters(to: &strokes, high: high)

    collectAppended(after: strokes, into: &freshSmearStrokes) {
      appendKnifeStroke(to: &$0, energy: energy, focus: focus)
    }

    appendPollockTrails(to: &strokes, energy: energy, focus: focus)

    let noPearl: Set<Int> = [2, 5]
    for i in strokes.indices where !noPearl.contains(Int(strokes[i].sizeOpacity.w)) {
      rollPearlescent(&strokes[i])
    }
    for i in freshSmearStrokes.indices { rollPearlescent(&freshSmearStrokes[i]) }

    strokes.append(contentsOf: enqueueAnimatingStrokes(freshSmearStrokes))

    return emitAnimatedStrokes(into: strokes)
  }

  func collectAppended(after base: [AbExStroke],
                       into fresh: inout [AbExStroke],
                       _ append: (inout [AbExStroke]) -> Void) {
    var scratch = base
    append(&scratch)
    fresh.append(contentsOf: scratch[base.count...])
  }

  private func strokeProgress(at t: Float,
                              drawDuration: Float,
                              extension ext: Float,
                              isWash: Bool) -> Float {
    if t < drawDuration {
      let u = t / drawDuration
      return isWash ? sqrt(u) : u
    }
    guard ext > 0 else { return 1.0 }
    return 1.0 + min((t - drawDuration) / ext, 1.0) * 0.35
  }

  func emitAnimatedStrokes(into base: [AbExStroke]) -> [AbExStroke] {
    var out = [AbExStroke]()
    for anim in animatingStrokes where out.count < Self.maxStrokesPerFrame {
      guard anim.elapsed > anim.previousElapsed else { continue }
      let typeRaw = Int(anim.stroke.sizeOpacity.w)
      let isWash = (typeRaw == 1)
      let ext = isWash ? 0 : Self.animationExtensionSeconds
      let drawDuration = anim.duration - ext

      let progressMin = anim.previousElapsed >= drawDuration
        ? 1.0
        : strokeProgress(at: anim.previousElapsed, drawDuration: drawDuration,
                         extension: ext, isWash: isWash)
      let progressMax = strokeProgress(at: anim.elapsed, drawDuration: drawDuration,
                                       extension: ext, isWash: isWash)
      var s = anim.stroke
      s.animation = SIMD4(progressMin, progressMax, 1, anim.stroke.animation.w)
      out.append(s)
    }
    for stroke in base where out.count < Self.maxStrokesPerFrame {
      out.append(stroke)
    }
    return out
  }
}

#endif
