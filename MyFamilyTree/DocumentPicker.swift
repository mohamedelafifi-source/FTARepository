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

/// A SwiftUI wrapper that lets the user pick a folder first, then shows all `.json` files in that folder.
struct JSONFileChooserView: View {
    // Callbacks
    var onPickJSON: (URL) -> Void
    var onCancel: () -> Void

    // UI state
    @State private var folderURL: URL? = nil
    @State private var jsonFiles: [URL] = []
    @State private var errorMessage: String? = nil

    var body: some View {
        Group {
            if let folderURL = folderURL {
                if !jsonFiles.isEmpty {
                    List(jsonFiles, id: \.self) { url in
                        Button(action: { onPickJSON(url) }) {
                            HStack {
                                Image(systemName: "doc.text")
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .navigationTitle(folderURL.lastPathComponent)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Refresh") {
                                loadJSONFiles(in: folderURL)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                        Text("No JSON files found in this folder.")
                            .font(.headline)
                        Button("Refresh") {
                            loadJSONFiles(in: folderURL)
                        }
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 16) {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                    Text("Select a storage folder first from the Location menu.")
                        .font(.headline)
                    Button(role: .cancel) { onCancel() } label: { Text("Close") }
                }
                .padding()
            }
        }
        .onAppear {
            if folderURL == nil, let globalFolder = GlobalVariables.shared.selectedFolderURL {
                let _ = globalFolder.startAccessingSecurityScopedResource()
                folderURL = globalFolder
                loadJSONFiles(in: globalFolder)
            }
        }
    }

    private func loadJSONFiles(in folder: URL) {
        errorMessage = nil
        jsonFiles.removeAll()

        do {
            // Enumerate non-recursively; change options if you want to include subfolders
            let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .nameKey]
            let fileManager = FileManager.default
            if let enumerator = fileManager.enumerator(
                at: folder,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) {
                var results: [URL] = []
                for case let fileURL as URL in enumerator {
                    let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                    guard values.isRegularFile == true else { continue }
                    if fileURL.pathExtension.lowercased() == "json" {
                        results.append(fileURL)
                    }
                }
                // Exclude the photo index file from the list
                results = results.filter { $0.lastPathComponent.lowercased() != "photo-index.json" }
                // Sort by name for stable display
                results.sort { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
                self.jsonFiles = results

                if results.isEmpty {
                    self.errorMessage = "No JSON files found in this folder."
                }
            } else {
                self.errorMessage = "Failed to read folder: Enumerator unavailable."
            }
        } catch {
            self.errorMessage = "Failed to read folder: \(error.localizedDescription)"
        }
    }
}

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

