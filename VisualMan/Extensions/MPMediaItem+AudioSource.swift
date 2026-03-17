//
//  MPMediaItem + AudioSource.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import Foundation
import MediaPlayer

private let thumbnailCache: NSCache<NSNumber, UIImage> = {
  let c = NSCache<NSNumber, UIImage>()
  c.countLimit = 75
  c.totalCostLimit = 10 * 1024 * 1024
  return c
}()

private let fullArtworkCache: NSCache<NSNumber, UIImage> = {
  let c = NSCache<NSNumber, UIImage>()
  c.countLimit = 50
  c.totalCostLimit = 50 * 1024 * 1024
  return c
}()

extension MPMediaItem: AudioSource {
  var albumArt: UIImage? {
    let key = NSNumber(value: persistentID)
    
    if let cachedArtwork = fullArtworkCache.object(forKey: key) { return cachedArtwork }
    
    guard let albumArt = artwork?.image(at: CGSize(width: 512, height: 512)) else { return nil }
    
    let cost = Int(albumArt.size.width * albumArt.size.height * 4)
    fullArtworkCache.setObject(albumArt, forKey: key, cost: cost)
    
    return albumArt
  }
  
  var thumbnailImage: UIImage? {
    let key = NSNumber(value: persistentID)
    
    if let cachedThumbnail = thumbnailCache.object(forKey: key) { return cachedThumbnail }
    
    guard let thumbnail = artwork?.image(at: CGSize(width: 60, height: 60)) else { return nil }
    
    let cost = Int(thumbnail.size.width * thumbnail.size.height * 4)
    thumbnailCache.setObject(thumbnail, forKey: key, cost: cost)
    
    return thumbnail
  }
  
  var duration: TimeInterval? {
    return playbackDuration
  }
  
  func getPlaybackURL() -> URL? {
    return assetURL
  }
}
