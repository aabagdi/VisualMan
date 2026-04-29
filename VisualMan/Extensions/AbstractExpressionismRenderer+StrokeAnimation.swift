//
//  AbstractExpressionismRenderer+StrokeAnimation.swift
//  VisualMan
//
//  Created by on 4/29/26.
//

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
      let totalFrames = (typeRaw == 4) ? Self.knifeAnimationFrames
                                        : Self.gesturalAnimationFrames
      animatingStrokes.append(AnimatingStroke(
        stroke: s, currentFrame: 0, totalFrames: totalFrames))
    }
  }

  private func generateGesturalCandidates(energy: Float,
                                          focus: SIMD2<Float>,
                                          spread: Float) -> [AbExStroke] {
    var candidates = [AbExStroke]()
    if energy > 0.05
        && (wallClock - lastGesturalTime) > 0.70
        && candidates.count < 12
        && nextSeed() < 0.45 {
      appendGesturalStroke(to: &candidates, energy: energy, focus: focus, spread: spread)
    }
    if energy > 0.25
        && (wallClock - lastGesturalTime) > 0.40
        && candidates.count < 12
        && nextSeed() < 0.10 {
      appendGesturalStroke(to: &candidates, energy: energy, focus: focus, spread: spread)
    }
    return candidates
  }

  func generateStrokes(audio: SIMD3<Float>) -> [AbExStroke] {
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

    appendWash(to: &strokes, mid: mid, focus: focus)
    appendAmbientWash(to: &strokes, energy: energy, focus: focus)
    appendRogueStroke(to: &strokes, energy: energy)
    appendScumble(to: &strokes, mid: mid, energy: energy, focus: focus)
    appendSplatters(to: &strokes, high: high)

    var preKnife = strokes
    appendKnifeStroke(to: &preKnife, energy: energy, focus: focus)
    let priorCount = strokes.count
    let knifeAdded = preKnife.count - priorCount
    for k in 0..<knifeAdded {
      freshSmearStrokes.append(preKnife[priorCount + k])
    }

    appendPollockTrails(to: &strokes, energy: energy, focus: focus)
    enqueueAnimatingStrokes(freshSmearStrokes)

    return emitAnimatedStrokes(into: strokes)
  }

  func emitAnimatedStrokes(into base: [AbExStroke]) -> [AbExStroke] {
    var out = base
    let extensionFrames = 8
    for anim in animatingStrokes where anim.currentFrame < anim.totalFrames
                                    && out.count < 12 {
      let drawFrames = anim.totalFrames - extensionFrames
      let cf = anim.currentFrame
      let progressMin: Float
      let progressMax: Float
      if cf < drawFrames {
        progressMin = Float(cf) / Float(drawFrames)
        progressMax = Float(cf + 1) / Float(drawFrames)
      } else {
        let extProg = Float(cf - drawFrames + 1) / Float(extensionFrames)
        progressMin = 1.0
        progressMax = 1.0 + extProg * 0.35
      }
      var s = anim.stroke
      s.animation = SIMD4(progressMin, progressMax, 1, anim.stroke.animation.w)
      out.append(s)
    }
    return out
  }
}
