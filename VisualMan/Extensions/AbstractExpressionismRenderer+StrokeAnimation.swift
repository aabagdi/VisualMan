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
        && (wallClock - lastGesturalTime) > 0.95
        && candidates.count < 12
        && nextSeed() < 0.32 {
      appendGesturalStroke(to: &candidates, energy: energy, focus: focus, spread: spread)
    }
    if energy > 0.25
        && (wallClock - lastGesturalTime) > 0.55
        && candidates.count < 12
        && nextSeed() < 0.07 {
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

    var preWash = strokes
    appendWash(to: &preWash, mid: mid, focus: focus)
    appendAmbientWash(to: &preWash, energy: energy, focus: focus)
    let washPriorCount = strokes.count
    let washAdded = preWash.count - washPriorCount
    for k in 0..<washAdded {
      freshSmearStrokes.append(preWash[washPriorCount + k])
    }

    appendRogueStroke(to: &strokes, energy: energy)

    var preScumble = strokes
    appendScumble(to: &preScumble, mid: mid, energy: energy, focus: focus)
    let scumblePriorCount = strokes.count
    let scumbleAdded = preScumble.count - scumblePriorCount
    for k in 0..<scumbleAdded {
      freshSmearStrokes.append(preScumble[scumblePriorCount + k])
    }

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
    for anim in animatingStrokes where anim.currentFrame < anim.totalFrames
                                    && out.count < 12 {
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
    return out
  }
}
