//
//  FileAudioSource.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import MediaPlayer
import AVFoundation

private struct ITunesMetadataResult {
  var title: String?
  var artist: String?
  var albumArt: UIImage?
}

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

    var albumArt = await loadArtwork(from: metadata, identifier: .commonIdentifierArtwork)

    if title == nil || artist == nil || albumArt == nil {
      if let iTunesMetadata = try? await asset.loadMetadata(for: .iTunesMetadata) {
        let result = await filliTunesMetadata(
          from: iTunesMetadata, title: title, artist: artist, albumArt: albumArt
        )
        title = result.title
        artist = result.artist
        albumArt = result.albumArt
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

  private static func loadArtwork(
    from metadata: [AVMetadataItem], identifier: AVMetadataIdentifier
  ) async -> UIImage? {
    guard let artworkItem = AVMetadataItem.metadataItems(
      from: metadata, filteredByIdentifier: identifier
    ).first,
      let imageData = try? await artworkItem.load(.dataValue) else { return nil }
    return UIImage(data: imageData)
  }

  private static func filliTunesMetadata(
    from iTunesMetadata: [AVMetadataItem],
    title: String?, artist: String?, albumArt: UIImage?
  ) async -> ITunesMetadataResult {
    var result = ITunesMetadataResult(title: title, artist: artist, albumArt: albumArt)
    if result.title == nil {
      result.title = try? await AVMetadataItem.metadataItems(
        from: iTunesMetadata,
        filteredByIdentifier: .iTunesMetadataSongName
      ).first?.load(.stringValue)
    }
    if result.artist == nil {
      result.artist = try? await AVMetadataItem.metadataItems(
        from: iTunesMetadata,
        filteredByIdentifier: .iTunesMetadataArtist
      ).first?.load(.stringValue)
    }
    if result.albumArt == nil {
      result.albumArt = await loadArtwork(from: iTunesMetadata, identifier: .iTunesMetadataCoverArt)
    }
    return result
  }
}
