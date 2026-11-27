//
//  AudioCAMetalLayerView+Present.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/25/26.
//

#if !targetEnvironment(simulator)
import Metal
import QuartzCore
import os

extension AudioCAMetalLayerView.Coordinator {
  func recoverFromStalledPresents() {
    guard let presentEvent, presentEvent.signaledValue < presentCount else { return }
    presentEvent.wait(untilSignaledValue: presentCount, timeoutMS: 250)
    if presentEvent.signaledValue < presentCount {
      presentEvent.signaledValue = presentCount
    }
  }

  func presentFrame(pipeline: any MTLRenderPipelineState,
                    intermediateTex: MTLTexture?,
                    drawable: CAMetalDrawable,
                    submitted: CFTimeInterval) {
    guard let presentCommandBuffer, let presentEvent else { return }
    let queue = renderer.commandQueue
    let inFlight = R.maxFramesInFlight

    let nextPresent = presentCount + 1
    if nextPresent > inFlight {
      let waitValue = nextPresent - inFlight
      if presentEvent.signaledValue < waitValue {
        presentEvent.wait(untilSignaledValue: waitValue, timeoutMS: 16)
        guard presentEvent.signaledValue >= waitValue else { return }
      }
    }
    presentCount = nextPresent
    let slot = Int(presentCount % inFlight)
    let allocator = presentAllocators[slot]
    allocator.reset()

    Self.encodeBlitPass(into: presentCommandBuffer,
                        allocator: allocator,
                        target: drawable.texture,
                        clearColor: clearColor,
                        pipeline: pipeline,
                        table: blitArgumentTables[slot],
                        source: intermediateTex)

    nonisolated(unsafe) let drawable = drawable
    let pacer = config.pacesFrameRate ? pacer : nil
    let firstFrameState = intermediateTex != nil ? firstFrameState : nil
    if firstFrameState != nil { self.firstFrameState = nil }
    let gate = PresentGate()
    let commitOptions = MTL4CommitOptions()
    commitOptions.addFeedbackHandler { @Sendable feedback in
      if let firstFrameState {
        pointsOfInterest.endInterval("Time to First Frame", firstFrameState)
      }
      if let error = feedback.error {
        blitLogger.error("Present pass failed: \(error.localizedDescription, privacy: .public)")
      }
      guard gate.markGPUCompleted(failed: feedback.error != nil) else { return }
      drawable.present()
      pacer?.frameCompleted(submitted: submitted)
    }

    queue.waitForDrawable(drawable)
    queue.commit([presentCommandBuffer], options: commitOptions)
    queue.signalDrawable(drawable)
    queue.signalEvent(presentEvent, value: presentCount)
    guard gate.markDrawableSignaled() else { return }
    drawable.present()
    pacer?.frameCompleted(submitted: submitted)
  }
}

#endif
