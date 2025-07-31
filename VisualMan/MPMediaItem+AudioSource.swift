//
//  MPMediaItem + AudioSource.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import Foundation
import MediaPlayer

extension MPMediaItem: AudioSource {
  var albumArt: UIImage? {
    return artwork?.image(at: CGSize(width: 512, height: 512))
  }
  
  var duration: TimeInterval? {
    return playbackDuration
  }
  
  func getPlaybackURL() -> URL? {
    return assetURL
  }
}
