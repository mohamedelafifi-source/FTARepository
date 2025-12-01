//
// FamilyImageHandling.swift
// MyFamilyTree
//
// Created by Mohamed El Afifi on 9/30/25.
//
import Foundation
import SwiftUI
import PhotosUI
import UIKit

// MARK: - ZoomableImageView Component
@available(iOS 16.0, *)
struct ZoomableImageView: View {
    let uiImage: UIImage
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale *= delta
                            scale = min(max(scale, 1.0), 5.0)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            if scale < 1.0 {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        },
                    DragGesture()
                        .onChanged { value in
                            let newOffset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
                            offset = newOffset
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut) {
                    scale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            }
    }
}

// MARK: - Image & Photo Handling (Single Source of Truth)
struct PhotoIndexEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var fileName: String
}

extension PhotoIndexEntry {
    static func compareByNameInsensitive(_ a: PhotoIndexEntry, _ b: PhotoIndexEntry) -> Bool {
        a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}

// Helper function to parse PhotoIndexEntry array from JSON Data with fallback parsing
private func parsePhotoIndexEntries(from data: Data) throws -> [PhotoIndexEntry] {
    if data.isEmpty { return [] }
    let jsonAny: Any = try JSONSerialization.jsonObject(with: data)
    var parsedArray: [PhotoIndexEntry] = []
    if let arrayOfDicts = jsonAny as? [[String: Any]] {
        for dict in arrayOfDicts {
            guard let name = dict["name"] as? String else { continue }
            let fileNameFromDict: String? = (dict["fileName"] as? String) ?? (dict["filename"] as? String)
            guard let fileName = fileNameFromDict else { continue }
            let entry = PhotoIndexEntry(name: name, fileName: fileName)
            parsedArray.append(entry)
        }
    } else if let dictOfDicts = jsonAny as? [String: Any] {
        for (key, value) in dictOfDicts {
            guard let valueDict = value as? [String: Any] else { continue }
            let fileNameFromValue: String? = (valueDict["fileName"] as? String) ?? (valueDict["filename"] as? String)
            guard let fileName = fileNameFromValue else { continue }
            let entry = PhotoIndexEntry(name: key, fileName: fileName)
            parsedArray.append(entry)
        }
    }
    return parsedArray
}

/// PhotoImportService
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

// MARK: - Access Resolution Utility (Outside the View)

/// Utility to hold the result of the complex bookmark resolution.
enum AccessResult {
    case success(folderURL: URL, indexURL: URL)
    case failure(message: String)
}

@available(iOS 16.0, *)
private func resolveBookmarkSynchronously(data: Data) -> AccessResult {
    do {
        var isStale = false
        let resolvedURL = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        
        print("[resolveBookmark] Resolved URL: \(resolvedURL.path)")
        print("[resolveBookmark] Is stale: \(isStale)")
        
        guard resolvedURL.startAccessingSecurityScopedResource() else {
            print("[resolveBookmark] FAILED to start accessing security scoped resource")
            return .failure(message: "Failed to gain security access for folder.")
        }
        
        print("[resolveBookmark] Successfully started accessing security scoped resource")
        
        let indexURL = resolvedURL.appendingPathComponent("photo-index.json")
        
        return .success(folderURL: resolvedURL, indexURL: indexURL)
    } catch {
        print("[resolveBookmark] Error: \(error.localizedDescription)")
        return .failure(message: error.localizedDescription)
    }
}

// ----------------------------------------------------------------------
// MARK: - PhotoBrowserView (Single Definition)
// ----------------------------------------------------------------------
@available(iOS 16.0, *)
struct PhotoBrowserView: View {
    let folderBookmark: Data
    
    private let accessStatus: AccessResult
    
    @State private var entries: [PhotoIndexEntry] = []
    @State private var selected: PhotoIndexEntry?
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteEntries: [PhotoIndexEntry] = []
    @State private var currentImage: UIImage?
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingDetailSheet = false
    @State private var sheetEntry: PhotoIndexEntry?

    init(folderBookmark: Data) {
        self.folderBookmark = folderBookmark
        self.accessStatus = resolveBookmarkSynchronously(data: folderBookmark)
    }
    
    var body: some View {
        Group {
            switch accessStatus {
            case .success(let folderURL, let indexURL):
                mainContent(folderURL: folderURL, indexURL: indexURL)
            case .failure(let message):
                errorView(message: message)
            }
        }
        .onAppear {
            if case .success(let folderURL, let indexURL) = accessStatus {
                Task { await loadIndex(folderURL: folderURL, indexURL: indexURL) }
            }
        }
        .onDisappear {
            if case .success(let folderURL, _) = accessStatus {
                folderURL.stopAccessingSecurityScopedResource()
                print("[PhotoBrowserView] Stopped security access.")
            }
        }
    }
    
    // MARK: - Helper to load image with proper resource management
    private func loadImage(from url: URL, folderURL: URL) -> UIImage? {
        // Don't start/stop on individual file - rely on folder access already established
        guard let data = try? Data(contentsOf: url) else {
            print("[loadImage] Failed to load data from: \(url.path)")
            return nil
        }
        guard let image = UIImage(data: data) else {
            print("[loadImage] Failed to create UIImage from data")
            return nil
        }
        print("[loadImage] Successfully loaded image from: \(url.lastPathComponent)")
        return image
    }
    
    private func mainContent(folderURL: URL, indexURL: URL) -> some View {
        NavigationSplitView {
            Group {
                if hSizeClass == .compact {
                    List {
                        ForEach(entries) { entry in
                            Button {
                                sheetEntry = entry
                                showingDetailSheet = true
                            } label: {
                                Text(entry.name)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            deleteEntries(at: offsets, folderURL: folderURL, indexURL: indexURL)
                        }
                    }
                    .sheet(isPresented: $showingDetailSheet) {
                        if let entry = sheetEntry {
                            NavigationStack {
                                VStack {
                                    let imgURL = folderURL.appendingPathComponent(entry.fileName)
                                    if let uiImage = loadImage(from: imgURL, folderURL: folderURL) {
                                        ZoomableImageView(uiImage: uiImage)
                                        Text(entry.name).font(.headline)
                                    } else {
                                        Image(systemName: "photo")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 120, height: 120)
                                            .foregroundColor(.gray)
                                        Text("(Image not found)")
                                            .font(.caption)
                                        Text(entry.name)
                                            .font(.headline)
                                    }
                                }
                                .padding()
                                .navigationTitle(entry.name)
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        Button("Exit") { showingDetailSheet = false }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    List(selection: $selected) {
                        ForEach(entries) { entry in
                            Text(entry.name).tag(entry as PhotoIndexEntry?)
                        }
                        .onDelete { offsets in
                            deleteEntries(at: offsets, folderURL: folderURL, indexURL: indexURL)
                        }
                    }
                }
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
                    if let uiImage = currentImage {
                        VStack {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 300)
                                .cornerRadius(12)
                                .shadow(radius: 8)
                            Text(entry.name).font(.headline)
                        }
                        .padding()
                    } else {
                        ProgressView("Loading...")
                    }
                } else {
                    Text("Select a name")
                }
            }
            .task(id: selected) {
                if let entry = selected {
                    let imgURL = folderURL.appendingPathComponent(entry.fileName)
                    currentImage = loadImage(from: imgURL, folderURL: folderURL)
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
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.red)
            Text("Failed to Load Photos")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private func deleteEntries(at offsets: IndexSet, folderURL: URL, indexURL: URL) {
        let toDelete = offsets.compactMap { index in
            entries.indices.contains(index) ? entries[index] : nil
        }
        pendingDeleteEntries = toDelete
        showDeleteConfirm = true
    }
    
    private func confirmDeletion(folderURL: URL, indexURL: URL) {
        if !pendingDeleteEntries.isEmpty {
            delete(entries: pendingDeleteEntries, folderURL: folderURL, indexURL: indexURL)
            pendingDeleteEntries.removeAll()
        } else if let entry = selected {
            delete(entries: [entry], folderURL: folderURL, indexURL: indexURL)
        }
    }
    
    private func delete(entries toDelete: [PhotoIndexEntry], folderURL: URL, indexURL: URL) {
        do {
            for entry in toDelete {
                let imgURL = folderURL.appendingPathComponent(entry.fileName)
                if imgURL.startAccessingSecurityScopedResource() {
                    defer { imgURL.stopAccessingSecurityScopedResource() }
                    if FileManager.default.fileExists(atPath: imgURL.path) {
                        try FileManager.default.removeItem(at: imgURL)
                    }
                }
            }
            
            let all = try StorageManager.shared.loadPhotoIndex(from: indexURL)
            let namesToDeleteSet = Set(toDelete.map { $0.fileName })
            let newIndex = all.filter { !namesToDeleteSet.contains($0.fileName) }
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(newIndex)
            try data.write(to: indexURL, options: .atomic)
            
            if let sel = selected, namesToDeleteSet.contains(sel.fileName) {
                selected = nil
                currentImage = nil
            }
            Task { await loadIndex(folderURL: folderURL, indexURL: indexURL) }
        } catch {
            print("[PhotoBrowserView] Delete error: \(error)")
        }
    }
    
    @MainActor
    private func loadIndex(folderURL: URL, indexURL: URL) async {
        do {
            let arr = try StorageManager.shared.loadPhotoIndex(from: indexURL)
            var tmpArr = arr
            tmpArr.sort(by: PhotoIndexEntry.compareByNameInsensitive)
            entries = tmpArr
            if hSizeClass == .regular, selected == nil {
                selected = entries.first
            }
        } catch {
            // Try fallback parser
            do {
                let parsed: [PhotoIndexEntry] = try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let data = try Data(contentsOf: indexURL)
                            let parsedArray = try parsePhotoIndexEntries(from: data)
                            continuation.resume(returning: parsedArray)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                var tmpParsed = parsed
                tmpParsed.sort(by: PhotoIndexEntry.compareByNameInsensitive)
                entries = tmpParsed
                if hSizeClass == .regular, selected == nil {
                    selected = entries.first
                }
            } catch {
                print("[PhotoBrowserView.loadIndex] Failed to read index: \(error.localizedDescription)")
            }
        }
    }
}

// ----------------------------------------------------------------------
// MARK: - FilteredPhotoBrowserView (Single Definition)
// ----------------------------------------------------------------------
@available(iOS 16.0, *)
struct FilteredPhotoBrowserView: View {
    let folderBookmark: Data
    let filterNames: [String]

    private let accessStatus: AccessResult

    @State private var entries: [PhotoIndexEntry] = []
    @State private var selected: PhotoIndexEntry?
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteEntries: [PhotoIndexEntry] = []
    @State private var currentImage: UIImage?
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.dismiss) private var dismiss

    @State private var showingDetailSheet = false
    @State private var sheetEntry: PhotoIndexEntry?

    private var filterSet: Set<String> {
        Set(filterNames.map { $0.lowercased() })
    }

    init(folderBookmark: Data, filterNames: [String]) {
        self.folderBookmark = folderBookmark
        self.filterNames = filterNames
        self.accessStatus = resolveBookmarkSynchronously(data: folderBookmark)
    }
    
    var body: some View {
        Group {
            switch accessStatus {
            case .success(let folderURL, let indexURL):
                mainContent(folderURL: folderURL, indexURL: indexURL)
            case .failure(let message):
                errorView(message: message)
            }
        }
        .onAppear {
            if case .success(let folderURL, let indexURL) = accessStatus {
                Task { await loadIndex(folderURL: folderURL, indexURL: indexURL) }
            }
        }
        .onDisappear {
            if case .success(let folderURL, _) = accessStatus {
                folderURL.stopAccessingSecurityScopedResource()
                print("[FilteredPhotoBrowserView] Stopped security access.")
            }
        }
    }
    
    // MARK: - Helper to load image with proper resource management
    private func loadImage(from url: URL, folderURL: URL) -> UIImage? {
        // Don't start/stop on individual file - rely on folder access already established
        guard let data = try? Data(contentsOf: url) else {
            print("[FilteredPhotoBrowserView.loadImage] Failed to load data from: \(url.path)")
            return nil
        }
        guard let image = UIImage(data: data) else {
            print("[FilteredPhotoBrowserView.loadImage] Failed to create UIImage from data")
            return nil
        }
        print("[FilteredPhotoBrowserView.loadImage] Successfully loaded image from: \(url.lastPathComponent)")
        return image
    }
    
    private func mainContent(folderURL: URL, indexURL: URL) -> some View {
        NavigationSplitView {
            Group {
                if hSizeClass == .compact {
                    List {
                        ForEach(entries) { entry in
                            Button {
                                sheetEntry = entry
                                showingDetailSheet = true
                            } label: {
                                Text(entry.name)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            deleteEntries(at: offsets, folderURL: folderURL, indexURL: indexURL)
                        }
                    }
                    .sheet(isPresented: $showingDetailSheet) {
                        if let entry = sheetEntry {
                            NavigationStack {
                                VStack {
                                    let imgURL = folderURL.appendingPathComponent(entry.fileName)
                                    if let uiImage = loadImage(from: imgURL, folderURL: folderURL) {
                                        ZoomableImageView(uiImage: uiImage)
                                        Text(entry.name).font(.headline)
                                    } else {
                                        Image(systemName: "photo")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 120, height: 120)
                                            .foregroundColor(.gray)
                                        Text("(Image not found)")
                                            .font(.caption)
                                        Text(entry.name)
                                            .font(.headline)
                                    }
                                }
                                .padding()
                                .navigationTitle(entry.name)
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        Button("Exit") { showingDetailSheet = false }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    List(selection: $selected) {
                        ForEach(entries) { entry in
                            Text(entry.name).tag(entry as PhotoIndexEntry?)
                        }
                        .onDelete { offsets in
                            deleteEntries(at: offsets, folderURL: folderURL, indexURL: indexURL)
                        }
                    }
                }
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
                    if let uiImage = currentImage {
                        VStack {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 300)
                                .cornerRadius(12)
                                .shadow(radius: 8)
                            Text(entry.name).font(.headline)
                        }
                        .padding()
                    } else {
                        ProgressView("Loading...")
                    }
                } else {
                    Text("Select a name")
                }
            }
            .task(id: selected) {
                if let entry = selected {
                    let imgURL = folderURL.appendingPathComponent(entry.fileName)
                    currentImage = loadImage(from: imgURL, folderURL: folderURL)
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
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.red)
            Text("Failed to Load Photos")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private func deleteEntries(at offsets: IndexSet, folderURL: URL, indexURL: URL) {
        let toDelete = offsets.compactMap { index in
            entries.indices.contains(index) ? entries[index] : nil
        }
        pendingDeleteEntries = toDelete
        showDeleteConfirm = true
    }
    
    private func confirmDeletion(folderURL: URL, indexURL: URL) {
        if !pendingDeleteEntries.isEmpty {
            delete(entries: pendingDeleteEntries, folderURL: folderURL, indexURL: indexURL)
            pendingDeleteEntries.removeAll()
        } else if let entry = selected {
            delete(entries: [entry], folderURL: folderURL, indexURL: indexURL)
        }
    }
    
    private func delete(entries toDelete: [PhotoIndexEntry], folderURL: URL, indexURL: URL) {
        do {
            for entry in toDelete {
                let imgURL = folderURL.appendingPathComponent(entry.fileName)
                if imgURL.startAccessingSecurityScopedResource() {
                    defer { imgURL.stopAccessingSecurityScopedResource() }
                    if FileManager.default.fileExists(atPath: imgURL.path) {
                        try FileManager.default.removeItem(at: imgURL)
                    }
                }
            }
            
            let all = try StorageManager.shared.loadPhotoIndex(from: indexURL)
            let namesToDeleteSet = Set(toDelete.map { $0.fileName })
            let newIndex = all.filter { !namesToDeleteSet.contains($0.fileName) }
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(newIndex)
            try data.write(to: indexURL, options: .atomic)
            
            if let sel = selected, namesToDeleteSet.contains(sel.fileName) {
                selected = nil
                currentImage = nil
            }
            Task { await loadIndex(folderURL: folderURL, indexURL: indexURL) }
        } catch {
            print("[FilteredPhotoBrowserView] Delete error: \(error)")
        }
    }
    
    @MainActor
    private func loadIndex(folderURL: URL, indexURL: URL) async {
        do {
            let arr = try StorageManager.shared.loadPhotoIndex(from: indexURL)
            var tmpArr = arr
            tmpArr.sort(by: PhotoIndexEntry.compareByNameInsensitive)
            // APPLY FILTER
            tmpArr = tmpArr.filter { filterSet.contains($0.name.lowercased()) }
            entries = tmpArr
            if hSizeClass == .regular, selected == nil {
                selected = entries.first
            }
        } catch {
            // Try fallback parser
            do {
                let parsed: [PhotoIndexEntry] = try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let data = try Data(contentsOf: indexURL)
                            let parsedArray = try parsePhotoIndexEntries(from: data)
                            continuation.resume(returning: parsedArray)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                var tmpParsed = parsed
                tmpParsed.sort(by: PhotoIndexEntry.compareByNameInsensitive)
                // APPLY FILTER
                tmpParsed = tmpParsed.filter { filterSet.contains($0.name.lowercased()) }
                entries = tmpParsed
                if hSizeClass == .regular, selected == nil {
                    selected = entries.first
                }
            } catch {
                print("[FilteredPhotoBrowserView.loadIndex] Failed to read index: \(error.localizedDescription)")
            }
        }
    }
}
