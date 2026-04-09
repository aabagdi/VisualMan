//
//  SmoothedAudio.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/9/26.
//

struct SmoothedAudio {
    var bass: Float = 0
    var mid: Float = 0
    var high: Float = 0
    var time: Float = 0

    mutating func update(from levels: InlineArray<1024, Float>, dt: Float) {
        bass = bass * 0.5 + levels.bassLevel * 0.5
        mid = mid * 0.6 + levels.midLevel * 0.4
        high = high * 0.4 + levels.highLevel * 0.6
        time += dt * (1.0 + bass * 0.5)
    }
}
