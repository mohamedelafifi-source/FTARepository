//
//  FamilyImageHandling.swift
//  MyFamilyTree
//
//  Created by Mohamed El Afifi on 9/30/25.
//

import Foundation
//
//  ImageHandling.swift
//  SwiftTreeTwo
//
//  Created by Mohamed El Afifi on 9/14/25.
//
import Foundation
import SwiftUI
import PhotosUI
import UIKit

// MARK: - Image & Photo Handling (Single Source of Truth)
// All photo-related models and utilities live here.

/// PhotoIndexEntry
/// Canonical model for entries in photo-index.json.
/// Centralized here alongside image/photo handling to keep related logic together.
/// Note: This type used to be duplicated in PhotoIndexEntry.swift, which caused
/// an "Invalid redeclaration" error. That file has been removed.
struct PhotoIndexEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var fileName: String
}
/*This means both PhotoImportService and PhotoBrowserView are only available on iOS 16.0 and later.
If you tried to use them from a context that might run on earlier iOS versions, the compiler would require you
 guard the usage.
*/
/// PhotoImportService
/// Canonical implementation for importing photos from PhotosPicker and updating the index.
/// Centralized here with other photo-related types to avoid duplicate declarations.
/// Note: The standalone PhotoImportService.swift file was removed to prevent
/// "Invalid redeclaration" compiler errors.
@available(iOS 16.0, *)

enum PhotoImportService {
    static func importFromPhotos(
        item: PhotosPickerItem,
        folderURL: URL,
        currentIndexURL: URL?,
        personName: String
    ) async throws -> (displayName: String, savedURL: URL, indexURL: URL) {
        guard let rawData = try await item.loadTransferable(type: Data.self) else {
            throw CocoaError(.fileReadUnknown)
        }
    

        // 2) Ensure we have an index JSON (create if needed)
        var indexURL = currentIndexURL
        if indexURL == nil {
            indexURL = try StorageManager.shared.ensurePhotoIndex(in: folderURL, fileName: "photo-index.json")
        }
        guard let idxURL = indexURL else {
            throw CocoaError(.fileNoSuchFile)
        }

        // 3) Normalize image → prefer JPEG, else PNG, else raw
        let image = UIImage(data: rawData)
        var dataToSave: Data
        var ext = "jpg"
        if let img = image, let jpg = img.jpegData(compressionQuality: 0.92) {
            dataToSave = jpg
            ext = "jpg"
        } else if let img = image, let png = img.pngData() {
            dataToSave = png
            ext = "png"
        } else {
            dataToSave = rawData
            ext = "jpg"
        }

        // 4) Person name is required
        let trimmedName = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: [NSLocalizedDescriptionKey: "Please enter a name for the photo owner before importing."])
        }
        let displayName = trimmedName

        // 5) Save to folder with PersonName-UUID.ext
        let savedURL = try StorageManager.shared.saveImageData(
            dataToSave,
            into: folderURL,
            preferredBaseName: displayName,
            ext: ext
        )

        // 6) Update index
        try StorageManager.shared.appendToPhotoIndex(
            name: displayName,
            fileName: savedURL.lastPathComponent,
            indexURL: idxURL
        )

        return (displayName, savedURL, idxURL)
    }
}
//
//  PhotoBrowserView.swift
//  SwiftTreeTwo
//

/// Simple browser for names/images stored via StorageManager + photo-index.json
/// Expects `PhotoIndexEntry` and `StorageManager` to already exist in the project.

@available(iOS 16.0, *)

struct PhotoBrowserView: View {
    let folderURL: URL
    let indexURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [PhotoIndexEntry] = []
    @State private var selected: PhotoIndexEntry?
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    @State private var pendingDeleteEntries: [PhotoIndexEntry] = []

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(entries) { entry in
                    Button {
                        selected = entry
                    } label: {
                        Text(entry.name).lineLimit(1)
                    }
                }
                .onDelete(perform: deleteEntries)
            }
            .navigationTitle("Photos")
            .onAppear(perform: loadIndex)
        } detail: {
            Group {
                if let entry = selected {
                    let imgURL = folderURL.appendingPathComponent(entry.fileName)
                    if let ui = UIImage(contentsOfFile: imgURL.path) {
                        ScrollView {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .padding()
                        }
                        .navigationTitle(entry.name)
                    } else {
                        Text("Image not found").foregroundColor(.secondary)
                    }
                } else {
                    Text("Select a name").foregroundColor(.secondary)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if selected != nil {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    confirmDeletion()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove the image file and its entry from the index.")
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        let toDelete = offsets.compactMap { entries.indices.contains($0) ? entries[$0] : nil }
        pendingDeleteEntries = toDelete
        showDeleteConfirm = true
    }

    private func confirmDeletion() {
        if !pendingDeleteEntries.isEmpty {
            delete(entries: pendingDeleteEntries)
            pendingDeleteEntries.removeAll()
        } else {
            deleteSelected()
        }
    }

    private func delete(entries toDelete: [PhotoIndexEntry]) {
        do {
            // Remove image files
            for entry in toDelete {
                let imgURL = folderURL.appendingPathComponent(entry.fileName)
                if FileManager.default.fileExists(atPath: imgURL.path) {
                    try FileManager.default.removeItem(at: imgURL)
                }
            }

            // Update JSON index
            let all = try StorageManager.shared.loadPhotoIndex(from: indexURL)
            let namesToDelete = Set(toDelete.map { $0.fileName })
            let newIndex = all.filter { !namesToDelete.contains($0.fileName) }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(newIndex)
            try data.write(to: indexURL, options: .atomic)

            // Refresh UI
            if let sel = selected, namesToDelete.contains(sel.fileName) {
                selected = nil
            }
            loadIndex()
        } catch {
            errorMessage = "Couldn't delete photo(s): \(error.localizedDescription)"
        }
    }

    private func deleteSelected() {
        guard let entry = selected else { return }
        delete(entries: [entry])
    }

    private func loadIndex() {
        do {
            let arr = try StorageManager.shared.loadPhotoIndex(from: indexURL)
            entries = arr.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            print("Failed to load photo index:", error.localizedDescription)
        }
    }
}

// MARK: - Filtered Photo Browser
/// Shows only photos whose names match a provided list (case-insensitive).
@available(iOS 16.0, *)
struct FilteredPhotoBrowserView: View {
    let folderURL: URL
    let indexURL: URL
    let filterNames: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [PhotoIndexEntry] = []
    @State private var selected: PhotoIndexEntry?
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    @State private var pendingDeleteEntries: [PhotoIndexEntry] = []

    private var filterSet: Set<String> {
        Set(filterNames.map { $0.lowercased() })
    }

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(entries) { entry in
                    Button {
                        selected = entry
                    } label: {
                        Text(entry.name).lineLimit(1)
                    }
                }
                .onDelete(perform: deleteEntries)
            }
            .navigationTitle("Tree Photos")
            .onAppear(perform: loadIndex)
        } detail: {
            Group {
                if let entry = selected {
                    let imgURL = folderURL.appendingPathComponent(entry.fileName)
                    if let ui = UIImage(contentsOfFile: imgURL.path) {
                        ScrollView {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .padding()
                        }
                        .navigationTitle(entry.name)
                    } else {
                        Text("Image not found").foregroundColor(.secondary)
                    }
                } else {
                    Text("Select a name").foregroundColor(.secondary)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if selected != nil {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    confirmDeletion()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove the image file and its entry from the index.")
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        let toDelete = offsets.compactMap { entries.indices.contains($0) ? entries[$0] : nil }
        pendingDeleteEntries = toDelete
        showDeleteConfirm = true
    }

    private func confirmDeletion() {
        if !pendingDeleteEntries.isEmpty {
            delete(entries: pendingDeleteEntries)
            pendingDeleteEntries.removeAll()
        } else {
            deleteSelected()
        }
    }

    private func delete(entries toDelete: [PhotoIndexEntry]) {
        do {
            // Remove image files
            for entry in toDelete {
                let imgURL = folderURL.appendingPathComponent(entry.fileName)
                if FileManager.default.fileExists(atPath: imgURL.path) {
                    try FileManager.default.removeItem(at: imgURL)
                }
            }

            // Update JSON index
            let all = try StorageManager.shared.loadPhotoIndex(from: indexURL)
            let namesToDelete = Set(toDelete.map { $0.fileName })
            let newIndex = all.filter { !namesToDelete.contains($0.fileName) }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(newIndex)
            try data.write(to: indexURL, options: .atomic)

            // Refresh UI (with filtering)
            if let sel = selected, namesToDelete.contains(sel.fileName) {
                selected = nil
            }
            loadIndex()
        } catch {
            errorMessage = "Couldn't delete photo(s): \(error.localizedDescription)"
        }
    }

    private func deleteSelected() {
        guard let entry = selected else { return }
        delete(entries: [entry])
    }

    private func loadIndex() {
        do {
            let all = try StorageManager.shared.loadPhotoIndex(from: indexURL)
            // Filter by names (case-insensitive)
            let filtered = all.filter { filterSet.contains($0.name.lowercased()) }
            entries = filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            selected = entries.first
        } catch {
            print("Failed to load photo index:", error.localizedDescription)
        }
    }
}

