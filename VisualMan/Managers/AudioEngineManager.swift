//
//  AudioEngineManager.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/13/25.
//

import Foundation
import AVFoundation
import Accelerate
import Combine
import MediaPlayer

@Observable
final class AudioEngineManager {
  static let shared = AudioEngineManager()
  
  var audioLevels: [Float] = Array(repeating: 0.0, count: 512)
  var visualizerBars: [Float] = Array(repeating: 0.0, count: 32)
  var isPlaying = false
  var currentTime: TimeInterval = 0
  var duration: TimeInterval = 0
  var isInitialized = false
  var failedToInitialize = false
  var initializationError: Error?
  var currentAudioSourceURL: URL?
  
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var audioFile: AVAudioFile?
  private var displayLink: CADisplayLink?
  private var securityScopedURL: URL?
  private var lastSeekFrame: AVAudioFramePosition = 0
  private var isSeeking: Bool = false
  private var numberOfBars = 32
  private var peakLevels: [Float] = Array(repeating: 0.0, count: 32)
  private var peakHoldTime: [Int] = Array(repeating: 0, count: 32)
  private var gainHistory: [Float] = []
  private var currentGain: Float = 1.0
  private var hasHandledCompletion = false
  private var isHandlingCompletion = false
  private var currentPlaybackID = UUID()
  private var nowPlayingTimer: Timer?
  private var lockScreenUpdateHandler: (() -> Void)?
  
  private let smoothingFactor: Float = 0.8
  private let attackTime: Float = 0.1
  private let releaseTime: Float = 0.6
  private let peakHoldDuration = 10
  private let gainHistorySize = 30
  
  let playbackCompleted = PassthroughSubject<Void, Never>()
  
  private init() {
    do {
      try setupAudioEngine()
      isInitialized = true
    } catch {
      initializationError = error
      isInitialized = false
      failedToInitialize = true
    }
  }
  
  isolated deinit {
    stopDisplayLink()
    stopSecurityScopedAccess()
  }
  
  private func setupAudioEngine() throws {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      throw Errors.invalidSession
    }
    
    engine = AVAudioEngine()
    
    player = AVAudioPlayerNode()
    
    guard let engine,
          let player else { return }
    
    _ = engine.mainMixerNode
    
    let format = engine.mainMixerNode.outputFormat(forBus: 0)
    
    engine.stop()
    
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
  }
  
  
  func play(_ source: AudioSource) throws {
    if currentAudioSourceURL == source.getPlaybackURL() && isPlaying { return }
    
    if player?.isPlaying == true {
      player?.stop()
    }
    
    engine?.mainMixerNode.removeTap(onBus: 0)
    
    audioLevels = Array(repeating: 0.0, count: 512)
    visualizerBars = Array(repeating: 0.0, count: 32)
    peakLevels = Array(repeating: 0.0, count: 32)
    peakHoldTime = Array(repeating: 0, count: 32)
    gainHistory = []
    currentGain = 1.0
    lastSeekFrame = 0
    
    guard let url = source.getPlaybackURL() else {
      throw Errors.invalidURL
    }
    
    try play(from: url)
    currentAudioSourceURL = source.getPlaybackURL()
  }
  
  private func play(from url: URL) throws {
    stopSecurityScopedAccess()
    
    let accessing = url.startAccessingSecurityScopedResource()
    
    if accessing {
      securityScopedURL = url
    }
    try playAudioFromURL(url)
  }
  
  private func playAudioFromURL(_ url: URL) throws {
    guard let engine,
          let player else {
      throw Errors.nilEngineOrPlayer
    }
    
    hasHandledCompletion = false
    isHandlingCompletion = false
    
    let playbackID = UUID()
    currentPlaybackID = playbackID
    
    do {
      audioFile = try AVAudioFile(forReading: url)
      
      guard let audioFile else {
        throw Errors.failedToCreateFile
      }
      
      duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
      
      engine.prepare()
      
      if !engine.isRunning {
        try engine.start()
      }
      
      player.scheduleFile(audioFile, at: nil) { [weak self] in
        DispatchQueue.main.async {
          guard let self,
                self.currentPlaybackID == playbackID else { return }
          self.handlePlaybackCompleted()
        }
      }
      
      DispatchQueue.main.async { [weak self] in
        self?.isPlaying = true
        self?.startDisplayLink()
      }
    } catch {
      DispatchQueue.main.async { [weak self] in
        self?.isPlaying = false
        self?.stopDisplayLink()
      }
      throw Errors.failedToPlay
    }
    
    let format = engine.mainMixerNode.outputFormat(forBus: 0)
    
    engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable [weak self] buffer, _ in
      guard let channelData = buffer.floatChannelData?[0] else { return }
      
      let frameLength = Int(buffer.frameLength)
      let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
      
      Task { @MainActor in
        self?.processAudioBuffer(samples)
      }
    }
    
    player.play()
  }
  
  private func stopSecurityScopedAccess() {
    if let url = securityScopedURL {
      url.stopAccessingSecurityScopedResource()
      securityScopedURL = nil
    }
  }
  
  private func handlePlaybackCompleted() {
    guard !hasHandledCompletion && !isHandlingCompletion else { return }
    
    isHandlingCompletion = true
    
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      
      self.hasHandledCompletion = true
      
      self.playbackCompleted.send()
      
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
        guard let self = self else { return }
        if self.hasHandledCompletion && !(self.player?.isPlaying ?? true) {
          self.isPlaying = false
          self.currentTime = self.duration
          self.stopDisplayLink()
        }
        self.isHandlingCompletion = false
      }
    }
  }
  
  func pause() {
    player?.pause()
    isPlaying = false
    stopDisplayLink()
  }
  
  func resume() {
    player?.play()
    isPlaying = true
    startDisplayLink()
  }
  
  func stop() {
    currentPlaybackID = UUID()
    player?.stop()
    engine?.mainMixerNode.removeTap(onBus: 0)
    engine?.stop()
    isPlaying = false
    currentTime = 0
    stopDisplayLink()
    stopSecurityScopedAccess()
    if !isSeeking {
      lastSeekFrame = 0
    }
    hasHandledCompletion = false
    isHandlingCompletion = false
    stopNowPlayingTimer()
    currentAudioSourceURL = nil
  }
  
  func seek(to time: TimeInterval) {
    guard let player,
          let audioFile else { return }
    
    isSeeking = true
    
    currentPlaybackID = UUID()
    
    let sampleRate = audioFile.fileFormat.sampleRate
    let newFrame = AVAudioFramePosition(time * sampleRate)
    
    let clampedFrame = max(0, min(newFrame, audioFile.length))
    
    lastSeekFrame = clampedFrame
    
    player.stop()
    
    if clampedFrame < audioFile.length {
      player.scheduleSegment(
        audioFile,
        startingFrame: clampedFrame,
        frameCount: AVAudioFrameCount(audioFile.length - clampedFrame),
        at: nil
      )
      
      if isPlaying {
        player.play()
      }
    }
    
    currentTime = time
    
    isSeeking = false
  }
  
  func startNowPlayingTimer(updateHandler: @escaping () -> Void) {
    stopNowPlayingTimer()
    lockScreenUpdateHandler = updateHandler
    nowPlayingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.lockScreenUpdateHandler?()
      }
    }
  }
  
  func stopNowPlayingTimer() {
    nowPlayingTimer?.invalidate()
    nowPlayingTimer = nil
    lockScreenUpdateHandler = nil
  }
  
  func startDisplayLink() {
    stopDisplayLink()
    displayLink = CADisplayLink(target: self, selector: #selector(updateTime))
    displayLink?.add(to: .current, forMode: .common)
  }
  
  func stopDisplayLink() {
    displayLink?.invalidate()
    displayLink = nil
  }
  
  @objc func updateTime() {
    guard let player,
          let audioFile,
          player.isPlaying else { return }
    
    if let nodeTime = player.lastRenderTime,
       let playerTime = player.playerTime(forNodeTime: nodeTime) {
      let sampleTime = playerTime.sampleTime
      
      guard sampleTime >= 0 else { return }
      
      let currentFrame = lastSeekFrame + sampleTime
      let newTime = Double(currentFrame) / audioFile.fileFormat.sampleRate
      
      if newTime >= 0 && newTime <= duration {
        currentTime = newTime
      }
      
      if currentTime >= duration - 0.05 && !isSeeking && !hasHandledCompletion {
        if currentFrame >= audioFile.length - Int64(audioFile.fileFormat.sampleRate * 0.05) {
          handlePlaybackCompleted()
        }
      }
    }
  }
  
  private func processAudioBuffer(_ samples: [Float]) {
    var realIn = [Float](repeating: 0, count: 1024)
    var imagIn = [Float](repeating: 0, count: 1024)
    var realOut = [Float](repeating: 0, count: 1024)
    var imagOut = [Float](repeating: 0, count: 1024)
    
    for i in 0..<min(samples.count, 1024) {
      let window = 0.5 - 0.5 * cos(2.0 * .pi * Float(i) / Float(1023))
      realIn[i] = samples[i] * window
    }
    
    guard let dftSetup = vDSP_DFT_zop_CreateSetup(nil, 1024, vDSP_DFT_Direction.FORWARD) else { return }
    
    vDSP_DFT_Execute(dftSetup, &realIn, &imagIn, &realOut, &imagOut)
    
    var magnitudes = [Float](repeating: 0.0, count: 512)
    
    realOut.withUnsafeBufferPointer { realPtr in
      imagOut.withUnsafeBufferPointer { imagPtr in
        guard let realBase = realPtr.baseAddress,
              let imagBase = imagPtr.baseAddress else { return }
        
        var complex = DSPSplitComplex(realp: UnsafeMutablePointer(mutating: realBase),
                                      imagp: UnsafeMutablePointer(mutating: imagBase))
        vDSP_zvabs(&complex, 1, &magnitudes, 1, 512)
      }
    }
    
    var scaleFactor: Float = 2.0 / Float(1024)
    vDSP_vsmul(magnitudes, 1, &scaleFactor, &magnitudes, 1, 512)
    
    var logMagnitudes = [Float](repeating: 0.0, count: 512)
    
    let sampleRate: Float = 44100.0
    let binFrequencyWidth = sampleRate / Float(1024)
    
    for i in 0..<512 {
      let frequency = Float(i) * binFrequencyWidth
      
      let f2 = frequency * frequency
      let f4 = f2 * f2
      
      let c1: Float = 12194.217 * 12194.217
      let c2: Float = 20.598997 * 20.598997
      let c3: Float = 107.65265 * 107.65265
      let c4: Float = 737.86223 * 737.86223
      
      let num = c1 * f4
      
      let term1 = f2 + c2
      let term2 = f2 + c3
      let term3 = f2 + c4
      let term4 = f2 + c1
      let sqrtTerm = sqrt(term2 * term3)
      let den = term1 * sqrtTerm * term4
      
      var aWeight: Float = 0.0
      if den > 0 && frequency > 10 {
        aWeight = 2.0 + 20.0 * log10(num / den)
      } else if frequency <= 10 {
        aWeight = -50.0
      }
      
      let aWeightLinear = pow(10.0, aWeight / 20.0)
      
      let magnitude = magnitudes[i] + 1e-10
      
      let weightedMagnitude = magnitude * aWeightLinear
      
      let db = 20.0 * log10(weightedMagnitude)
      
      let normalized = (db + 60.0) / 80.0
      
      logMagnitudes[i] = max(0.0, min(1.0, normalized))
    }
    
    for i in 0..<512 {
      audioLevels[i] = audioLevels[i] * 0.8 + logMagnitudes[i] * 0.2
    }
    
    let newBars = createVisualizerBars(from: audioLevels)
    
    updateAutomaticGainControl(bars: newBars)
    
    for i in 0..<numberOfBars {
      let currentLevel = visualizerBars[i]
      let targetLevel = newBars[i] * currentGain
      
      if targetLevel > currentLevel {
        visualizerBars[i] = currentLevel + (targetLevel - currentLevel) * (1.0 - attackTime)
      } else {
        visualizerBars[i] = currentLevel + (targetLevel - currentLevel) * (1.0 - releaseTime)
      }
      
      visualizerBars[i] = min(1.0, visualizerBars[i])
      
      if visualizerBars[i] > peakLevels[i] {
        peakLevels[i] = visualizerBars[i]
        peakHoldTime[i] = peakHoldDuration
      } else if peakHoldTime[i] > 0 {
        peakHoldTime[i] -= 1
      } else {
        peakLevels[i] *= 0.95
      }
    }
    
    vDSP_DFT_DestroySetup(dftSetup)
  }
  
  private func updateAutomaticGainControl(bars: [Float]) {
    let maxBar = bars.max() ?? 0.0
    
    gainHistory.append(maxBar)
    if gainHistory.count > gainHistorySize {
      gainHistory.removeFirst()
    }
    
    let averagePeak = gainHistory.reduce(0, +) / Float(gainHistory.count)
    
    let targetPeak: Float = 0.75
    var desiredGain: Float = 1.0
    
    if averagePeak > 0.01 {
      desiredGain = targetPeak / averagePeak
    }
    
    desiredGain = max(0.3, min(2.0, desiredGain))
    
    currentGain = currentGain * 0.95 + desiredGain * 0.05
  }
  
  private func createVisualizerBars(from fftData: [Float]) -> [Float] {
    var bars = [Float](repeating: 0, count: numberOfBars)
    
    let minFreq: Float = 60.0
    let maxFreq: Float = 16000.0
    let sampleRate: Float = 44100.0
    
    let logMinFreq = log10(minFreq)
    let logMaxFreq = log10(maxFreq)
    
    for i in 0..<numberOfBars {
      let logFreqLow = logMinFreq + (logMaxFreq - logMinFreq) * Float(i) / Float(numberOfBars)
      let logFreqHigh = logMinFreq + (logMaxFreq - logMinFreq) * Float(i + 1) / Float(numberOfBars)
      
      let freqLow = pow(10, logFreqLow)
      let freqHigh = pow(10, logFreqHigh)
      
      let binWidth = sampleRate / Float(fftData.count * 2)
      let binLow = Int(freqLow / binWidth)
      let binHigh = Int(freqHigh / binWidth)
      
      let startBin = max(0, min(binLow, fftData.count - 1))
      let endBin = max(startBin + 1, min(binHigh, fftData.count))
      
      var maxMag: Float = 0
      var avgMag: Float = 0
      var count = 0
      
      for j in startBin..<endBin {
        let mag = fftData[j]
        avgMag += mag
        maxMag = max(maxMag, mag)
        count += 1
      }
      
      if count > 0 {
        avgMag /= Float(count)
        bars[i] = avgMag * 0.7 + maxMag * 0.3
        
        let freqCenter = (freqLow + freqHigh) / 2.0
        
        if freqCenter < 200 {
          bars[i] *= 1.5
        } else if freqCenter < 500 {
          bars[i] *= 1.2
        }
        
        bars[i] = tanh(bars[i] * 2.0) / 2.0
        
        bars[i] = max(0, min(1, bars[i]))
      }
    }
    
    return bars
  }
}
