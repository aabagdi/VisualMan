//
//  FilePickerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import SwiftUI
import UIKit
internal import UniformTypeIdentifiers

struct FilePickerView: UIViewControllerRepresentable {
  @Binding var selectedFileURL: URL?
  let onFilePicked: (URL) -> Void
  
  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.audio])
    
    controller.allowsMultipleSelection = false
    controller.shouldShowFileExtensions = true
    controller.delegate = context.coordinator
    
    return controller
  }
  
  func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
    
  }
  
  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }
  
  class Coordinator: NSObject, UIDocumentPickerDelegate {
    let parent: FilePickerView
    
    init(_ parent: FilePickerView) {
      self.parent = parent
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
      guard let url = urls.first else { return }
      parent.selectedFileURL = url
      parent.onFilePicked(url)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    }
  }
  
  typealias UIViewControllerType = UIDocumentPickerViewController
}
