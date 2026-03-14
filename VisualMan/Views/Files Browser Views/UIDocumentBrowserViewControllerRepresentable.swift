//
//  UIDocumentBrowserViewControllerRepresentable.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/13/26.
//

import SwiftUI
internal import UniformTypeIdentifiers

struct UIDocumentBrowserViewControllerRepresentable: UIViewControllerRepresentable {
  var onDocumentPicked: (URL) -> Void
  
  func makeCoordinator() -> Coordinator {
    Coordinator(onDocumentPicked: onDocumentPicked)
  }
  
  func makeUIViewController(context: Context) -> UIDocumentBrowserViewController {
    let controller = UIDocumentBrowserViewController(forOpening: [.aiff, .mp3, .wav, .mpeg4Audio])
    controller.allowsDocumentCreation = false
    controller.allowsPickingMultipleItems = false
    controller.delegate = context.coordinator
    return controller
  }
  
  func updateUIViewController(_ uiViewController: UIDocumentBrowserViewController, context: Context) { }
  
  class Coordinator: NSObject, UIDocumentBrowserViewControllerDelegate {
    var onDocumentPicked: (URL) -> Void
    
    init(onDocumentPicked: @escaping (URL) -> Void) {
      self.onDocumentPicked = onDocumentPicked
    }
    
    func documentBrowser(_ controller: UIDocumentBrowserViewController, didPickDocumentsAt documentURLs: [URL]) {
      guard let url = documentURLs.first else { return }
      onDocumentPicked(url)
    }
  }
}
