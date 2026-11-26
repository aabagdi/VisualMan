//
//  HapticsManager.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/24/26.
//

import AVFoundation
import CoreHaptics
import os
import Sharing

@Observable
@MainActor
final class HapticsManager {
  enum Constants {
    static let chunkDuration: TimeInterval = 1.0
    static let scheduleAhead: TimeInterval = 0.75
    static let startLead: TimeInterval = 0.05
    static let discontinuityTolerance: TimeInterval = 0.04
    static let playerLinger: TimeInterval = 0.5
    static let engineRetryDelay: TimeInterval = 1.0
    static let analysisRetryDelay: TimeInterval = 5.0
    static let curvePointLimit = 16
    static let strengthRange: ClosedRange<Double> = 0.2...1.8
    nonisolated static let defaultStrength: Double = 1
    static let strengthSnapDistance: Double = 0.05
  }

  private enum EngineState {
    case stopped
    case starting
    case running
  }

  private struct ScheduledPlayer {
    let player: any CHHapticPatternPlayer
    let endTime: TimeInterval
  }

  @ObservationIgnored @Shared(.hapticsEnabled) private var storedIsEnabled
  @ObservationIgnored @Shared(.hapticsStrength) private var storedStrength

  var isEnabled: Bool {
    get { storedIsEnabled }
    set {
      $storedIsEnabled.withLock { $0 = newValue }
      if newValue {
        startAnalysis()
      } else {
        halt()
        if track == nil {
          analysisTask?.cancel()
          analysisTask = nil
        }
      }
    }
  }

  var strength: Double {
    get { min(max(storedStrength, Constants.strengthRange.lowerBound), Constants.strengthRange.upperBound) }
    set {
      let oldValue = strength
      $storedStrength.withLock { $0 = newValue }
      if strength != oldValue {
        cancelScheduledPlayers()
      }
    }
  }

  var isSupported: Bool { engine != nil }

  var isActive: Bool {
    get { isSupported && isEnabled }
    set { isEnabled = newValue }
  }

  @ObservationIgnored private let logger = Logger(subsystem: "com.VisualMan", category: "HapticsManager")
  @ObservationIgnored private let engine: CHHapticEngine?

  @ObservationIgnored private var engineState = EngineState.stopped
  @ObservationIgnored private var wantsEngine = false
  @ObservationIgnored private var engineRetryTime: TimeInterval = 0
  @ObservationIgnored private var track: BassHapticTrack?
  @ObservationIgnored private var trackURL: URL?
  @ObservationIgnored private var analysisRetryTime: TimeInterval = 0
  @ObservationIgnored private var analysisTask: Task<Void, Never>?
  @ObservationIgnored private var scheduledPlayers: [ScheduledPlayer] = []
  @ObservationIgnored private var scheduledThrough: TimeInterval?
  @ObservationIgnored private var lastTick: (position: TimeInterval, time: TimeInterval)?
  @ObservationIgnored private var outputLatency: TimeInterval = 0
  @ObservationIgnored private var routeChangeObserver: (any NSObjectProtocol)?

  init() {
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
          let engine = try? CHHapticEngine(audioSession: .sharedInstance()) else {
      engine = nil
      return
    }
    self.engine = engine

    engine.playsHapticsOnly = true
    engine.stoppedHandler = { @Sendable [weak self] _ in
      Task { @MainActor in
        self?.handleEngineStopped()
      }
    }
    engine.resetHandler = { @Sendable [weak self] in
      Task { @MainActor in
        self?.handleEngineStopped()
      }
    }

    routeChangeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance(),
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.handleRouteChange()
      }
    }
  }

  isolated deinit {
    analysisTask?.cancel()
    if let routeChangeObserver {
      NotificationCenter.default.removeObserver(routeChangeObserver)
    }
  }

  func loadTrack(at url: URL) {
    analysisTask?.cancel()
    analysisTask = nil
    cancelScheduledPlayers()
    track = nil
    trackURL = url
    analysisRetryTime = 0
    outputLatency = AVAudioSession.sharedInstance().outputLatency
    startAnalysis()
  }

  func resync() {
    cancelScheduledPlayers()
  }

  func advance(to position: TimeInterval, hostTime: UInt64) {
    guard isEnabled, let engine else { return }
    let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
    guard let track else {
      startAnalysis(at: now)
      return
    }

    wantsEngine = true
    guard engineState == .running else {
      startEngine(at: now)
      return
    }

    let songNow = position + now - AVAudioTime.seconds(forHostTime: hostTime)
    if let lastTick,
       abs(songNow - (lastTick.position + now - lastTick.time)) > Constants.discontinuityTolerance {
      cancelScheduledPlayers()
    }
    lastTick = (songNow, now)
    scheduledPlayers.removeAll { $0.endTime < now }

    let earliestStart = songNow + Constants.startLead
    if let scheduledThrough, scheduledThrough < earliestStart {
      cancelScheduledPlayers()
    }

    let chunkStart = scheduledThrough ?? earliestStart
    guard chunkStart - songNow < Constants.scheduleAhead else { return }

    var pulses = Array(track.pulses(startingIn: chunkStart ..< chunkStart + Constants.chunkDuration))
    if scheduledThrough == nil, let resumed = track.pulse(activeAt: chunkStart)?.resumed(at: chunkStart) {
      pulses.insert(resumed, at: 0)
    }
    scheduledThrough = chunkStart + Constants.chunkDuration
    guard !pulses.isEmpty else { return }

    do {
      try schedule(pulses, from: chunkStart, after: chunkStart - songNow + outputLatency, on: engine, now: now)
    } catch {
      logger.error("Failed to schedule haptics: \(error.localizedDescription)")
      handleEngineStopped()
      engineRetryTime = now + Constants.engineRetryDelay
    }
  }

  func halt() {
    wantsEngine = false
    cancelScheduledPlayers()
    guard engineState == .running else { return }
    engineState = .stopped
    engine?.stop(completionHandler: nil)
  }

  private func schedule(
    _ pulses: [BassPulse],
    from chunkStart: TimeInterval,
    after delay: TimeInterval,
    on engine: CHHapticEngine,
    now: TimeInterval
  ) throws {
    var sustains: [CHHapticEvent] = []
    var curves: [CHHapticParameterCurve] = []
    var transients: [CHHapticEvent] = []
    var patternDuration: TimeInterval = 0

    for pulse in pulses {
      let offset = pulse.start - chunkStart
      sustains.append(
        CHHapticEvent(
          eventType: .hapticContinuous,
          parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(min(strength, 1))),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: pulse.sharpness)
          ],
          relativeTime: offset,
          duration: pulse.duration
        )
      )
      curves.append(contentsOf: intensityCurves(for: pulse, at: offset, gain: Float(max(strength, 1))))
      if let transient = pulse.transient {
        transients.append(
          CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
              CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: min(transient.intensity * Float(strength), 1)
              ),
              CHHapticEventParameter(parameterID: .hapticSharpness, value: transient.sharpness)
            ],
            relativeTime: offset
          )
        )
      }
      patternDuration = max(patternDuration, offset + pulse.duration)
    }

    let startTime = engine.currentTime + delay
    let endTime = now + delay + patternDuration + Constants.playerLinger

    let sustainPlayer = try engine.makePlayer(with: CHHapticPattern(events: sustains, parameterCurves: curves))
    try sustainPlayer.start(atTime: startTime)
    scheduledPlayers.append(ScheduledPlayer(player: sustainPlayer, endTime: endTime))

    guard !transients.isEmpty else { return }
    let transientPlayer = try engine.makePlayer(with: CHHapticPattern(events: transients, parameters: []))
    try transientPlayer.start(atTime: startTime)
    scheduledPlayers.append(ScheduledPlayer(player: transientPlayer, endTime: endTime))
  }

  private func startEngine(at now: TimeInterval) {
    guard let engine, engineState == .stopped, now >= engineRetryTime else { return }
    engineState = .starting
    engine.start { @Sendable [weak self] error in
      Task { @MainActor in
        self?.handleEngineStarted(error: error)
      }
    }
  }

  private func handleEngineStarted(error: (any Error)?) {
    guard engineState == .starting else { return }

    if let error {
      logger.error("Failed to start haptic engine: \(error.localizedDescription)")
      engineState = .stopped
      engineRetryTime = AVAudioTime.seconds(forHostTime: mach_absolute_time()) + Constants.engineRetryDelay
    } else if wantsEngine {
      engineState = .running
    } else {
      engineState = .stopped
      engine?.stop(completionHandler: nil)
    }
  }

  private func handleEngineStopped() {
    engineState = .stopped
    scheduledPlayers.removeAll()
    scheduledThrough = nil
    lastTick = nil
  }
}

private extension HapticsManager {
  func handleRouteChange() {
    outputLatency = AVAudioSession.sharedInstance().outputLatency
    cancelScheduledPlayers()
  }

  func cancelScheduledPlayers() {
    for scheduled in scheduledPlayers {
      try? scheduled.player.cancel()
    }
    scheduledPlayers.removeAll()
    scheduledThrough = nil
    lastTick = nil
  }

  func startAnalysis(at now: TimeInterval = AVAudioTime.seconds(forHostTime: mach_absolute_time())) {
    guard engine != nil, isEnabled, track == nil, analysisTask == nil, now >= analysisRetryTime,
          let url = trackURL else { return }

    analysisTask = Task(priority: .utility) { [weak self] in
      let analysisState = pointsOfInterest.beginInterval("Bass Haptic Analysis")
      defer { pointsOfInterest.endInterval("Bass Haptic Analysis", analysisState) }
      do {
        let track = try await BassHapticAnalyzer.analyze(url: url)
        guard !Task.isCancelled else { return }
        self?.track = track
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled, let self else { return }
        self.logger.error("Failed to analyze bass for haptics: \(error.localizedDescription)")
        self.analysisTask = nil
        self.analysisRetryTime = AVAudioTime.seconds(forHostTime: mach_absolute_time())
          + Constants.analysisRetryDelay
      }
    }
  }

  func intensityCurves(for pulse: BassPulse, at offset: TimeInterval, gain: Float) -> [CHHapticParameterCurve] {
    let points = pulse.envelope
    var curves: [CHHapticParameterCurve] = []
    var index = 0

    while index < points.count - 1 {
      let end = min(index + Constants.curvePointLimit, points.count)
      let first = points[index]
      let controlPoints = points[index ..< end].map {
        CHHapticParameterCurve.ControlPoint(
          relativeTime: $0.time - first.time,
          value: min($0.intensity * gain, 1)
        )
      }
      curves.append(
        CHHapticParameterCurve(
          parameterID: .hapticIntensityControl,
          controlPoints: controlPoints,
          relativeTime: offset + first.time
        )
      )
      index = end - 1
    }

    return curves
  }
}
