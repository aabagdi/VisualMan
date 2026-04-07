//
//  FileAudioSource.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import MediaPlayer

struct FileAudioSource: AudioSource {
  let url: URL?
  let title: String?
  let artist: String?
  let duration: TimeInterval?
  let albumArt: UIImage?
  let thumbnailImage: UIImage?
  
  init(url: URL,
       title: String? = nil,
       artist: String? = nil,
       duration: TimeInterval? = nil,
       albumArt: UIImage? = nil,
       thumbnailImage: UIImage? = nil) {
    self.url = url
    self.title = title ?? url.deletingPathExtension().lastPathComponent
    self.artist = artist
    self.duration = duration
    self.albumArt = albumArt
    self.thumbnailImage = thumbnailImage
  }
  
  func getPlaybackURL() -> URL? {
    return url
  }
}
