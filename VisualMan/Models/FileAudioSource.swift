//
//  FileAudioSource.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import MediaPlayer
import AVFoundation

struct FileAudioSource: AudioSource {
  let url: URL
  let title: String?
  let artist: String?
  let duration: TimeInterval?
  let albumArt: UIImage?
  let thumbnailImage: UIImage?
  let isSecurityScoped: Bool

  init(url: URL,
       title: String? = nil,
       artist: String? = nil,
       duration: TimeInterval? = nil,
       albumArt: UIImage? = nil,
       thumbnailImage: UIImage? = nil,
       isSecurityScoped: Bool = false) {
    self.url = url
    self.title = title ?? url.deletingPathExtension().lastPathComponent
    self.artist = artist
    self.duration = duration
    self.albumArt = albumArt
    self.thumbnailImage = thumbnailImage
    self.isSecurityScoped = isSecurityScoped
  }

  func getPlaybackURL() -> URL? {
    return url
  }

  static func from(url: URL, isSecurityScoped: Bool) async throws -> FileAudioSource {
    let asset = AVURLAsset(url: url)
    let metadata = try await asset.load(.commonMetadata)

    var title = try? await AVMetadataItem.metadataItems(
      from: metadata,
      filteredByIdentifier: .commonIdentifierTitle
    ).first?.load(.stringValue)

    var artist = try? await AVMetadataItem.metadataItems(
      from: metadata,
      filteredByIdentifier: .commonIdentifierArtist
    ).first?.load(.stringValue)

    var albumArt: UIImage?
    if let artworkItem = AVMetadataItem.metadataItems(
      from: metadata,
      filteredByIdentifier: .commonIdentifierArtwork
    ).first {
      if let imageData = try? await artworkItem.load(.dataValue) {
        albumArt = UIImage(data: imageData)
      }
    }

    if title == nil || artist == nil || albumArt == nil {
      if let iTunesMetadata = try? await asset.loadMetadata(for: .iTunesMetadata) {
        if title == nil {
          title = try? await AVMetadataItem.metadataItems(
            from: iTunesMetadata,
            filteredByIdentifier: .iTunesMetadataSongName
          ).first?.load(.stringValue)
        }
        if artist == nil {
          artist = try? await AVMetadataItem.metadataItems(
            from: iTunesMetadata,
            filteredByIdentifier: .iTunesMetadataArtist
          ).first?.load(.stringValue)
        }
        if albumArt == nil {
          if let artworkItem = AVMetadataItem.metadataItems(
            from: iTunesMetadata,
            filteredByIdentifier: .iTunesMetadataCoverArt
          ).first {
            if let imageData = try? await artworkItem.load(.dataValue) {
              albumArt = UIImage(data: imageData)
            }
          }
        }
      }
    }

    return FileAudioSource(
      url: url,
      title: title,
      artist: artist,
      albumArt: albumArt,
      isSecurityScoped: isSecurityScoped
    )
  }
}
