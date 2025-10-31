//
//  DocumentPicker.swift
//  MyFamilyTree
//
//  Created by Mohamed El Afifi on 9/30/25.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Pass `contentTypes` including `UTType.folder` to allow selecting directories.
struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType]
    var allowsMultipleSelection: Bool = false
    var onPick: ([URL]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: false)
        // Do not constrain to a specific directory so the user can browse iCloud Drive and On My Device
        picker.directoryURL = nil
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = context.coordinator
        // Prefer opening mode to pick existing files/folders; export/import modes are not needed here
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // no update needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // Start security-scoped access for each picked URL
            var accessibleURLs: [URL] = []
            for url in urls {
                let _ = url.startAccessingSecurityScopedResource()
                accessibleURLs.append(url)
            }
            parent.onPick(accessibleURLs)
            // Do not stopAccessing here if the caller needs ongoing access; they can stop later.
            // If you prefer to stop here, uncomment the following:
            // for url in accessibleURLs { url.stopAccessingSecurityScopedResource() }
        }
    }
}
