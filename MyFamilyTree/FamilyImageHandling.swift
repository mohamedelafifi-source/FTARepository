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
struct PhotoIndexEntry: Identifiable, Codable, Hashable {
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
        // Start accessing the folder URL before doing anything
        guard folderURL.startAccessingSecurityScopedResource() else {
            print("[PhotoImportService] FAILED to gain security access for folder.")
            throw CocoaError(.fileReadNoPermission)
        }
        
        // Defer stopping access until the function returns
        defer {
            folderURL.stopAccessingSecurityScopedResource()
            print("[PhotoImportService] Stopped security access.")
        }
        
        print("[PhotoImportService] Gained security access for folder.")
        
        guard let rawData = try await item.loadTransferable(type: Data.self) else {
            throw CocoaError(.fileReadUnknown)
        }
        
        
        // 2) Ensure we have an index JSON (create if needed)
        // We use the passed-in currentIndexURL which was derived from the "live" folderURL
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
        
        let attrs = try? FileManager.default.attributesOfItem(atPath: savedURL.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        print("[PhotoImportService] Saved image:", savedURL.path, "size=", size)
        
        // 6) Update index
        try StorageManager.shared.appendToPhotoIndex(
            name: displayName,
            fileName: savedURL.lastPathComponent,
            indexURL: idxURL
        )
        
        print("[PhotoImportService] Appended to photo-index.json for:", displayName)
        
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
    // ========== MODIFICATION 1: Accept the bookmark DATA, not the URL ==========
    let folderBookmark: Data
    
    // ========== MODIFICATION 2: Use @State for resolved URLs ==========
    @State private var resolvedFolderURL: URL?
    @State private var resolvedIndexURL: URL?
    
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [PhotoIndexEntry] = []
    @State private var selected: PhotoIndexEntry?
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    @State private var pendingDeleteEntries: [PhotoIndexEntry] = []
    @Environment(\.horizontalSizeClass) private var hSizeClass
    
    // ========== MODIFICATION 3: Main body is now conditional ==========
    var body: some View {
        return Group {
            
            if let folderURL = resolvedFolderURL, let indexURL = resolvedIndexURL {
                // This is the original body, which now only runs *after*
                // the URLs are resolved and permissions are granted.
                NavigationSplitView {
                    List(selection: $selected) {
                        ForEach(entries) { entry in
                            Text(entry.name)
                                .lineLimit(1)
                                .tag(entry)
                        }
                        .onDelete(perform: { offsets in
                            deleteEntries(at: offsets, folderURL: folderURL, indexURL: indexURL)
                        })
                    }
                    .navigationTitle("Photos")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { dismiss() }
                        }
                    }
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
                            confirmDeletion(folderURL: folderURL, indexURL: indexURL)
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This will remove the image file and its entry from the index.")
                    }
                }
            } else if errorMessage != nil {
                // Show an error if resolving/loading fails
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(errorMessage ?? "Failed to load photos.")
                        .font(.headline)
                    Text("Please try re-selecting the folder from the 'Location' menu.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                // Show a loading indicator
                ProgressView("Accessing Folder...")
            }
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        // ========== MODIFICATION 4: New .onAppear / .onDisappear logic ==========
        .onAppear(perform: resolveAndLoad)
        .onDisappear(perform: stopAccess)
    }
    
    private func resolveAndLoad() {
        var isStale = false
        do {
            // 1. Resolve the bookmark data to get a "live" URL
            let url = try URL(resolvingBookmarkData: folderBookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            // 2. Start access for the FOLDER *first*
            if !url.startAccessingSecurityScopedResource() {
                print("[PhotoBrowserView] FAILED to gain security access for FOLDER: \(url.path)")
                errorMessage = "[PhotoBrowserView.resolveAndLoad @\(#fileID):\(#line)] Could not get permission to read the folder: \(url.path)"
                print(errorMessage ?? "")
                return
            }
            
            // 3. NOW create the "live" index URL
            let idx = url.appendingPathComponent("photo-index.json")

            // 4. Start access for the FILE
            if !idx.startAccessingSecurityScopedResource() {
                print("[PhotoBrowserView] FAILED to gain security access for FILE: \(idx.path)")
                errorMessage = "[PhotoBrowserView.resolveAndLoad @\(#fileID):\(#line)] Could not get permission to read the photo index file: \(idx.path)"
                print(errorMessage ?? "")
                url.stopAccessingSecurityScopedResource() // Stop folder access
                return
            }
            
            print("[PhotoBrowserView] Access granted for folder and index file")
            
            // 5. SUCCESS: Set the state variables
            self.resolvedFolderURL = url
            self.resolvedIndexURL = idx

            // 6. Load the index
            Task { await loadIndex(folderURL: url, indexURL: idx) }
            
        } catch {
            errorMessage = "[PhotoBrowserView.resolveAndLoad @\(#fileID):\(#line)] Failed to resolve folder permission. Please re-select the folder. Error: \(error.localizedDescription)"
            print(errorMessage ?? "")
            print("[PhotoBrowserView] Failed to resolve bookmark: \(error)")
        }
    }
    
    private func stopAccess() {
        resolvedIndexURL?.stopAccessingSecurityScopedResource()
        resolvedFolderURL?.stopAccessingSecurityScopedResource()
        print("[PhotoBrowserView] Stopped security access.")
    }
    
    private func deleteEntries(at offsets: IndexSet, folderURL: URL, indexURL: URL) {
        let toDelete = offsets.compactMap { entries.indices.contains($0) ? entries[$0] : nil }
        pendingDeleteEntries = toDelete
        showDeleteConfirm = true
    }
    
    private func confirmDeletion(folderURL: URL, indexURL: URL) {
        if !pendingDeleteEntries.isEmpty {
            delete(entries: pendingDeleteEntries, folderURL: folderURL, indexURL: indexURL)
            pendingDeleteEntries.removeAll()
        } else {
            deleteSelected(folderURL: folderURL, indexURL: indexURL)
        }
    }
    
    private func delete(entries toDelete: [PhotoIndexEntry], folderURL: URL, indexURL: URL) {
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
            Task { await loadIndex(folderURL: folderURL, indexURL: indexURL) }
        } catch {
            errorMessage = "[PhotoBrowserView.delete @\(#fileID):\(#line)] Couldn't delete photo(s). Error: \(error.localizedDescription)"
        }
    }
    
    private func deleteSelected(folderURL: URL, indexURL: URL) {
        guard let entry = selected else { return }
        delete(entries: [entry], folderURL: folderURL, indexURL: indexURL)
    }
    //To read the photo index .JSON File . Where the error happens
    //============================================================
    @MainActor private func loadIndex(folderURL: URL, indexURL: URL) async {
        do {
            // First try the canonical loader
            do {
                let arr = try StorageManager.shared.loadPhotoIndex(from: indexURL)
                entries = arr.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if hSizeClass == .regular, selected == nil { selected = entries.first }
                print("[PhotoBrowserView] Loaded entries:", entries.count)
                return
            } catch {
                // fallback follows
            }

            // Fallback loader wrapped in async continuation and background queue
            let parsed = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[PhotoIndexEntry], Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let data = try Data(contentsOf: indexURL)
                        if data.isEmpty {
                            continuation.resume(returning: [])
                            return
                        }
                        let json = try JSONSerialization.jsonObject(with: data)
                        var parsed: [PhotoIndexEntry] = []
                        if let arr = json as? [[String: Any]] {
                            parsed = arr.compactMap { dict in
                                guard let name = dict["name"] as? String else { return nil }
                                let fileName = (dict["fileName"] as? String) ?? (dict["filename"] as? String)
                                guard let fileName else { return nil }
                                return PhotoIndexEntry(name: name, fileName: fileName)
                            }
                        } else if let dict = json as? [String: Any] {
                            parsed = dict.compactMap { (key, value) in
                                guard let v = value as? [String: Any] else { return nil }
                                let fileName = (v["fileName"] as? String) ?? (v["filename"] as? String)
                                guard let fileName else { return nil }
                                return PhotoIndexEntry(name: key, fileName: fileName)
                            }
                        }
                        continuation.resume(returning: parsed)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            entries = parsed.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if hSizeClass == .regular, selected == nil { selected = entries.first }
            print("[PhotoBrowserView] Loaded entries:", entries.count)
            return
            
        } catch {
            errorMessage = "[PhotoBrowserView.loadIndex @\(#fileID):\(#line)] Line 406..Failed to read photo index at: \(indexURL.path). The data may be missing or unreadable. Error at 406: \(error.localizedDescription)"
        }
    }
}

// MARK: - Filtered Photo Browser
@available(iOS 16.0, *)
struct FilteredPhotoBrowserView: View {
    // ========== MODIFICATION 1: Accept the bookmark DATA, not the URL ==========
    let folderBookmark: Data
    let filterNames: [String]

    // ========== MODIFICATION 2: Use @State for resolved URLs ==========
    @State private var resolvedFolderURL: URL?
    @State private var resolvedIndexURL: URL?
    
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [PhotoIndexEntry] = []
    @State private var selected: PhotoIndexEntry?
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    @State private var pendingDeleteEntries: [PhotoIndexEntry] = []
    @Environment(\.horizontalSizeClass) private var hSizeClass
    
    private var filterSet: Set<String> {
        Set(filterNames.map { $0.lowercased() })
    }
    
    // ========== MODIFICATION 3: Main body is now conditional ==========
    var body: some View {
        return Group {
            if let folderURL = resolvedFolderURL, let indexURL = resolvedIndexURL {
                // This is the original body, which now only runs *after*
                // the URLs are resolved and permissions are granted.
                NavigationSplitView {
                    List(selection: $selected) {
                        ForEach(entries) { entry in
                            Text(entry.name)
                                .lineLimit(1)
                                .tag(entry)
                        }
                        .onDelete(perform: { offsets in
                            deleteEntries(at: offsets, folderURL: folderURL, indexURL: indexURL)
                        })
                    }
                    .navigationTitle("Tree Photos")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { dismiss() }
                        }
                    }
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
                            confirmDeletion(folderURL: folderURL, indexURL: indexURL)
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This will remove the image file and its entry from the index.")
                    }
                }
            } else if errorMessage != nil {
                // Show an error if resolving/loading fails
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(errorMessage ?? "Failed to load photos.")
                        .font(.headline)
                    Text("Please try re-selecting the folder from the 'Location' menu.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                // Show a loading indicator
                ProgressView("Accessing Folder...")
            }
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        // ========== MODIFICATION 4: New .onAppear / .onDisappear logic ==========
        .onAppear(perform: resolveAndLoad)
        .onDisappear(perform: stopAccess)
    }
    
    private func resolveAndLoad() {
        var isStale = false
        do {
            // 1. Resolve the bookmark data to get a "live" URL
            let url = try URL(resolvingBookmarkData: folderBookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            // 2. Start access for the FOLDER *first*
            if !url.startAccessingSecurityScopedResource() {
                print("[FilteredPhotoBrowserView] FAILED to gain security access for FOLDER: \(url.path)")
                errorMessage = "[FilteredPhotoBrowserView.resolveAndLoad @\(#fileID):\(#line)] Could not get permission to read the folder: \(url.path)"
                print(errorMessage ?? "")
                return
            }
            
            // 3. NOW create the "live" index URL
            let idx = url.appendingPathComponent("photo-index.json")

            // 4. Start access for the FILE
            if !idx.startAccessingSecurityScopedResource() {
                print("[FilteredPhotoBrowserView] FAILED to gain security access for FILE: \(idx.path)")
                errorMessage = "[FilteredPhotoBrowserView.resolveAndLoad @\(#fileID):\(#line)] Could not get permission to read the photo index file: \(idx.path)"
                print(errorMessage ?? "")
                url.stopAccessingSecurityScopedResource() // Stop folder access
                return
            }
            
            print("[FilteredPhotoBrowserView] Access granted for folder and index file")
            
            // 5. SUCCESS: Set the state variables
            self.resolvedFolderURL = url
            self.resolvedIndexURL = idx

            // 6. Load the index
            Task { await loadIndex(folderURL: url, indexURL: idx) }
            
        } catch {
            errorMessage = "[FilteredPhotoBrowserView.resolveAndLoad @\(#fileID):\(#line)] Failed to resolve folder permission. Please re-select the folder. Error: \(error.localizedDescription)"
            print(errorMessage ?? "")
            print("[FilteredPhotoBrowserView] Failed to resolve bookmark: \(error)")
        }
    }
    
    private func stopAccess() {
        resolvedIndexURL?.stopAccessingSecurityScopedResource()
        resolvedFolderURL?.stopAccessingSecurityScopedResource()
        print("[FilteredPhotoBrowserView] Stopped security access.")
    }

    
    private func deleteEntries(at offsets: IndexSet, folderURL: URL, indexURL: URL) {
        let toDelete = offsets.compactMap { entries.indices.contains($0) ? entries[$0] : nil }
        pendingDeleteEntries = toDelete
        showDeleteConfirm = true
    }
    
    private func confirmDeletion(folderURL: URL, indexURL: URL) {
        if !pendingDeleteEntries.isEmpty {
            delete(entries: pendingDeleteEntries, folderURL: folderURL, indexURL: indexURL)
            pendingDeleteEntries.removeAll()
        } else {
            deleteSelected(folderURL: folderURL, indexURL: indexURL)
        }
    }
    
    private func delete(entries toDelete: [PhotoIndexEntry], folderURL: URL, indexURL: URL) {
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
            Task { await loadIndex(folderURL: folderURL, indexURL: indexURL) }
        } catch {
            errorMessage = "[FilteredPhotoBrowserView.delete @\(#fileID):\(#line)] Couldn't delete photo(s). Error: \(error.localizedDescription)"
        }
    }
    
    private func deleteSelected(folderURL: URL, indexURL: URL) {
        guard let entry = selected else { return }
        delete(entries: [entry], folderURL: folderURL, indexURL: indexURL)
    }
    
    @MainActor private func loadIndex(folderURL: URL, indexURL: URL) async {
        do {
            // First try the canonical loader
            do {
                let all = try StorageManager.shared.loadPhotoIndex(from: indexURL)
                let filtered = all.filter { filterSet.contains($0.name.lowercased()) }
                entries = filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if hSizeClass == .regular {
                    selected = entries.first
                } else {
                    selected = nil
                }
                print("[FilteredPhotoBrowserView] Loaded filtered entries:", entries.count)
                return
            } catch {
                // fallback follows
            }

            // Fallback loader wrapped in async continuation and background queue
            let parsed = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[PhotoIndexEntry], Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let data = try Data(contentsOf: indexURL)
                        if data.isEmpty {
                            continuation.resume(returning: [])
                            return
                        }
                        
                        let json = try JSONSerialization.jsonObject(with: data)
                        var parsed: [PhotoIndexEntry] = []
                        
                        if let arr = json as? [[String: Any]] {
                            parsed = arr.compactMap { dict in
                                guard let name = dict["name"] as? String else { return nil }
                                let fileName = (dict["fileName"]as? String) ?? (dict["filename"] as? String)
                                guard let fileName else { return nil }
                                return PhotoIndexEntry(name: name, fileName: fileName)
                            }
                        } else if let dict = json as? [String: Any] {
                            parsed = dict.compactMap { (key, value) in
                                guard let v = value as? [String: Any] else { return nil }
                                let fileName = (v["fileName"] as? String) ?? (v["filename"] as? String)
                                guard let fileName else { return nil }
                                return PhotoIndexEntry(name: key, fileName: fileName)
                            }
                        }
                        
                        continuation.resume(returning: parsed)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            // Apply filtering and update on main actor (self)
            let filtered = parsed.filter { filterSet.contains($0.name.lowercased()) }
            entries = filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if hSizeClass == .regular {
                selected = entries.first
            } else {
                selected = nil
            }
            print("[FilteredPhotoBrowserView] Loaded filtered entries:", entries.count)
            
        } catch {
            errorMessage = "[FilteredPhotoBrowserView.loadIndex @\(#fileID):\(#line)] AT 709 Failed to read photo index at: \(indexURL.path). Data may be missing or unreadable. Error at 709: \(error.localizedDescription)"
        }
    }
}

