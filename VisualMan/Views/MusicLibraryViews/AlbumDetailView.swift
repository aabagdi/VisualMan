//
//  AlbumDetailView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/28/25.
//

import SwiftUI
import Dependencies
import MediaPlayer

struct AlbumDetailView: View {
  let album: MPMediaItemCollection

  @Dependency(AudioEngineManager.self) private var audioManager

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private static let placeholder = UIImage(resource: .artPlaceholder)

  private var year: String {
    if let year = album.representativeItem?.value(forProperty: "year") as? Int, year > 0 {
      return String(year)
    } else {
      return String(localized: "Unknown")
    }
  }

  var body: some View {
    let albumArt = album.representativeItem?.albumArt ?? Self.placeholder
    let sortedSongs = album.items.sorted {
      ($0.discNumber, $0.albumTrackNumber) < ($1.discNumber, $1.albumTrackNumber)
    }
    
    List {
      Section {
        VStack(spacing: 12) {
          Image(uiImage: albumArt)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 4)
            .frame(maxWidth: 300)
            .accessibilityHidden(true)
            .accessibilityIgnoresInvertColors()
          
          VStack(spacing: 4) {
            Text(album.representativeItem?.albumTitle ?? String(localized: "Unknown"))
              .font(.title2)
              .fontWeight(.semibold)
              .multilineTextAlignment(.center)
            
            if album.representativeItem?.isCompilation == true {
              Text("Various Artists")
                .font(.body)
                .foregroundStyle(.secondary)
            } else {
              Text(album.representativeItem?.albumArtist ?? String(localized: "Unknown"))
                .font(.body)
                .foregroundStyle(.secondary)
            }
            
            HStack {
              Text(album.representativeItem?.genre ?? String(localized: "Unknown"))
              Text("•")
              Text(year)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
      }
      
      Section {
        ForEach(sortedSongs.enumerated(), id: \.element.persistentID) { index, song in
          let isCurrentSong = song.assetURL == audioManager.currentAudioSourceURL
          NavigationLink {
            MusicPlayerView(sortedSongs, startingIndex: index)
          } label: {
            HStack(spacing: 12) {
              if isCurrentSong {
                NowPlayingIndicatorView(isAnimating: audioManager.isPlaying)
                  .foregroundStyle(.tint)
                  .frame(minWidth: 20, alignment: .trailing)
              } else {
                Text("\(song.albumTrackNumber)")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                  .frame(minWidth: 20, alignment: .trailing)
              }
              
              VStack(alignment: .leading, spacing: 2) {
                Text(song.title ?? String(localized: "Unknown"))
                  .font(.body)
                  .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                  .foregroundStyle(isCurrentSong ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                
                if album.representativeItem?.isCompilation == true,
                   let artist = song.artist {
                  Text(artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                }
              }
              
              Spacer()
              
              if let duration = song.playbackDuration.formattedDuration() {
                Text(duration)
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
            }
            .padding(.vertical, 4)
          }
          .accessibilityAddTraits(isCurrentSong ? .isSelected : [])
        }
      }
    }
    .listStyle(.insetGrouped)
    .toolbarVisibility(.hidden, for: .tabBar)
    .modifier(SettingsToolbarButton())
  }
  
}
