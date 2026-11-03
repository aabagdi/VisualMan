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
    animatingStrokes.removeAll { $0.currentFrame >= $0.totalFrames }
    for i in animatingStrokes.indices {
      animatingStrokes[i].currentFrame += 1
    }
  }

  func enqueueAnimatingStrokes(_ fresh: [AbExStroke]) {
    for s in fresh where animatingStrokes.count < Self.maxAnimatingStrokes {
      let typeRaw = Int(s.sizeOpacity.w)
      let totalFrames: Int
      switch typeRaw {
      case 4:  totalFrames = Self.knifeAnimationFrames
      case 1:  totalFrames = Self.washAnimationFrames
      case 5:  totalFrames = Self.scumbleAnimationFrames
      default: totalFrames = Self.gesturalAnimationFrames
      }
      animatingStrokes.append(AnimatingStroke(
        stroke: s, currentFrame: 0, totalFrames: totalFrames))
    }
  }

  private func generateGesturalCandidates(energy: Float,
                                          focus: SIMD2<Float>,
                                          spread: Float) -> [AbExStroke] {
    var candidates = [AbExStroke]()
    if energy > 0.05
        && (wallClock - lastGesturalTime) > 1.8
        && candidates.count < Self.maxStrokesPerFrame
        && nextSeed() < 0.16 {
      appendGesturalStroke(to: &candidates, energy: energy, focus: focus, spread: spread)
    }
    if energy > 0.25
        && (wallClock - lastGesturalTime) > 1.1
        && candidates.count < Self.maxStrokesPerFrame
        && nextSeed() < 0.035 {
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

    enqueueAnimatingStrokes(freshSmearStrokes)

    return emitAnimatedStrokes(into: strokes)
  }

  func collectAppended(after base: [AbExStroke],
                       into fresh: inout [AbExStroke],
                       _ append: (inout [AbExStroke]) -> Void) {
    var scratch = base
    append(&scratch)
    fresh.append(contentsOf: scratch[base.count...])
  }

  func emitAnimatedStrokes(into base: [AbExStroke]) -> [AbExStroke] {
    var out = [AbExStroke]()
    for anim in animatingStrokes where anim.currentFrame < anim.totalFrames
                                    && out.count < Self.maxStrokesPerFrame {
      let typeRaw = Int(anim.stroke.sizeOpacity.w)
      let isWash = (typeRaw == 1)
      let extensionFrames = isWash ? 0 : 8
      let drawFrames = anim.totalFrames - extensionFrames
      let cf = anim.currentFrame
      let progressMin: Float
      let progressMax: Float
      if cf < drawFrames {
        let tMin = Float(cf) / Float(drawFrames)
        let tMax = Float(cf + 1) / Float(drawFrames)

        if isWash {
          progressMin = sqrt(tMin)
          progressMax = sqrt(tMax)
        } else {
          progressMin = tMin
          progressMax = tMax
        }
      } else {
        let extProg = Float(cf - drawFrames + 1) / Float(extensionFrames)
        progressMin = 1.0
        progressMax = 1.0 + extProg * 0.35
      }
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
