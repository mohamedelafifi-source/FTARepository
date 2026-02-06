//
//  ContentView.swift
//  MyFamilyTree
//

import SwiftUI
import AVFoundation
import AudioToolbox
import UIKit
import UniformTypeIdentifiers
import Combine
import PhotosUI
import Foundation


// Uses shared GlobalVariables and ExportPayload defined elsewhere in the project.
// TempExportDocument is defined in FileHandling.swift

struct ContentView: View {
    @ObservedObject var globals = GlobalVariables.shared
    @ObservedObject private var dataManager = FamilyDataManager.shared
    
    @State private var pendingFileHandlingCommand: FileHandlingCommand? = nil
    
    // Stable binding to present the exporter
    private var showExporterBinding: Binding<Bool> {
        Binding(
            get: { globals.showExporter },
            set: { globals.showExporter = $0 }
        )
    }
    
    // Added state for new clear data confirmation alert
    @State private var showDataEntryClearAlert = false
    
    // UI state
    @State private var showFolderPicker = false
    @State private var showJSONPicker = false
    @State private var showGallery = false
    @State private var showPhotoImporter = false
    @State private var pickedItem: PhotosPickerItem?
    //To enter the person name
    @State private var showNamePrompt = false
    @State private var tempNameInput = ""
    
    @State private var pendingPhotoName: String = ""  // optional; set name before importing
    
    @State private var bulkText = ""
    @State private var showBulkEditor = false
    @State private var showIndividualEntry = false
    @State private var showFamilyTree = false
    @State private var showFileHandling = false
    @State private var treeDetent: PresentationDetent = .large
    
    @State private var originalMembers: [String: FamilyMember] = [:]
    
    @State private var showConfirmation = false
    @State private var entryMode: EntryMode = .bulk
    
    // Exporter state
    @State private var exportingNow = false
    @State private var exportDoc = TempExportDocument(data: Data())
    @State private var exportType: UTType = .plainText
    @State private var exportName = "Export"
    
    // Alerts
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showSuccess = false
    @State private var successMessage = ""
    
    // New state variables for filtered photo view
    @State private var showFilteredPhotos = false
    @State private var filteredNamesForPhotos: [String] = []
    @State private var showAllAttachments = false  // ← ADDED FOR ATTACHMENTS BROWSER
    
    // Prevent overlapping Photo imports/presentations
    @State private var isImportingPhoto = false
    
    @State private var isHandlingJSONPick = false
    
    @State private var pendingLoadURL: URL? = nil
    
    // Added state for system file importer for JSON tree file loading
    @State private var showJSONFileImporter = false
    @State private var showJSONChooser = false
    @State private var showJSONAppendChooser = false
    
    // Added state to prevent overlapping presentation transitions
    @State private var isPresentingTransition = false
    
    // Added state for reset photo index confirmation dialog
    @State private var showResetPhotoIndexConfirm = false
    
    enum EntryMode: String, CaseIterable {
        case bulk = "Bulk"
        case individual = "Individual"
    }
    
    // ========== MODIFICATION: Use bookmark to check path ==========
    // Display helper for the Location menu path line
    fileprivate var folderPathDisplay: String {
        // Try to resolve from bookmark first
        if let url = resolveFolderURL(showError: false) {
            return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        } else if let url = globals.selectedFolderURL {
            // Fallback to transient URL if bookmark is gone
            return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        } else {
            return "None selected"
        }
    }
    
    // ========== MODIFICATION: Use bookmark to check status ==========
    // Simple flag for Location menu state (kept out of the view builder)
    fileprivate var isFolderSelected: Bool {
        // Check if the bookmark data exists
        UserDefaults.standard.data(forKey: "selectedFolderBookmark") != nil
    }
    
    // Helper to queue an export (handled by onReceive)
    fileprivate func queueExport(_ payload: ExportPayload) {
        globals.exportPayload = payload
    }
    
    // Auto-unique filenames
    fileprivate func stamped(_ base: String, ext: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        return "\(base)-\(fmt.string(from: Date())).\(ext)"
    }
    
    // New helpers for JSON loading and validation
    fileprivate func loadMembers(from url: URL) throws -> [FamilyMember] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([FamilyMember].self, from: data)
    }

    fileprivate func isLikelyJSON(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "json"
    }
    
    fileprivate func readIndexNames(from indexURL: URL) throws -> Set<String> {
        let data = try Data(contentsOf: indexURL)
        // Attempt to decode as an array of entries with a 'name' field
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let names = array.compactMap { $0["name"] as? String }
            return Set(names)
        }
        // Attempt to decode as a dictionary mapping name -> entries
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return Set(dict.keys)
        }
        return []
    }
    
    // ========== This is the core bookmark logic (UNCHANGED) ==========
    private func resolveFolderURL(showError: Bool) -> URL? {
        // 1. Get the saved permission data
        guard let bookmarkData = UserDefaults.standard.data(forKey: "selectedFolderBookmark") else {
            if showError {
                print("[ContentView] No folder permission bookmark found. User must re-select folder.")
                alertMessage = "No folder selected. Please choose a folder from the 'Location' menu."
                showAlert = true
            }
            return nil
        }
        
        do {
            var isStale = false
            // 2. Re-create a NEW, "live" URL from the permission data
            let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if isStale {
                // If the bookmark is stale, we should re-save it.
                print("[ContentView] Bookmark was stale, attempting to refresh...")
                let newBookmarkData = try resolvedURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(newBookmarkData, forKey: "selectedFolderBookmark")
                print("[ContentView] Refreshed stale bookmark.")
            }
            
            // 3. Return the new, "live" URL
            return resolvedURL
        } catch {
            if showError {
                print("[ContentView] Failed to resolve bookmark: \(error)")
                alertMessage = "Failed to get folder permission. Please re-select the folder from the 'Location' menu."
                showAlert = true
            }
            return nil
        }
    }
    
    fileprivate enum PhotoIndexError: LocalizedError {
        case folderNotSelected
        case noPermission
        case ensureFailed(Error)
        var errorDescription: String? {
            switch self {
            case .folderNotSelected:
                return "No storage folder selected. Please choose a folder from the Location menu."
            case .noPermission:
                return "Could not get permission to access the selected folder."
            case .ensureFailed(let underlying):
                return "Failed to read or create the photo index: \(underlying.localizedDescription)"
            }
        }
    }

    fileprivate func currentPhotoIndexURL() throws -> URL {
        guard let folder = resolveFolderURL(showError: true) else {
            throw PhotoIndexError.folderNotSelected
        }
        guard folder.startAccessingSecurityScopedResource() else {
            throw PhotoIndexError.noPermission
        }
        defer { folder.stopAccessingSecurityScopedResource() }
        do {
            let idx = try StorageManager.shared.ensurePhotoIndex(in: folder, fileName: "photo-index.json")
            return idx
        } catch {
            throw PhotoIndexError.ensureFailed(error)
        }
    }
    
    private func prepareExport(for payload: ExportPayload) {
        switch payload {
        case .none:
            break
        case .text(let s, let name):
            exportDoc = TempExportDocument(data: Data(s.utf8))
            exportType = .plainText
            exportName = name.isEmpty ? stamped("READ_ME", ext: "txt") : name
        case .json(let jsonString, let name):
            exportDoc = TempExportDocument(data: Data(jsonString.utf8))
            exportType = .json
            let final = name.isEmpty ? stamped("database", ext: "json") : (name.hasSuffix(".json") ? name : "\(name).json")
            exportName = final
        case .image(let bytes, let name, let type):
            exportDoc = TempExportDocument(data: bytes)
            exportType = type
            exportName = name
        }
    }

    private func handlePickedItem(_ item: PhotosPickerItem) async {
        defer { pickedItem = nil }
        
        // Get the "live" folder URL
        guard let folder = resolveFolderURL(showError: true) else {
            alertMessage = "No storage folder selected. Please choose a folder from the Location menu."
            showAlert = true
            return
        }
        
        // Get the "live" index URL with explicit error
        let index: URL
        do {
            index = try currentPhotoIndexURL()
        } catch {
            alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showAlert = true
            return
        }
        
        do {
            // We must start access before calling the import service
            // NOTE: The import service will ALSO start/stop its own access
            // but we do it here to be safe.
            guard folder.startAccessingSecurityScopedResource() else {
                throw CocoaError(.fileReadNoPermission)
            }
            
            defer { folder.stopAccessingSecurityScopedResource() }
            
            let result = try await PhotoImportService.importFromPhotos(
                item: item,
                folderURL: folder,
                currentIndexURL: index,
                personName: pendingPhotoName
            )
            // Keep photo index separate; do not overwrite tree JSON URL here.
            successMessage = "Imported"
            showSuccess = true
        } catch {
            let nsErr = error as NSError
            if nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSUserCancelledError {
                // user cancelled picker
            } else {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
    //=========
    //MAIN Menu
    //=========
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            LocationMenu(
                showFolderPicker: $showFolderPicker,
                folderPathDisplay: folderPathDisplay,
                isFolderSelected: isFolderSelected,
                onSelectFolderTapped: {
                    // Menu was triggered to select a folder; actual URL assignment happens in FolderPickerView completion
                }
            )
            
        }
        
        ToolbarItem(placement: .topBarLeading) {
            fileHandlingMenu
        }
        ToolbarItem(placement: .topBarLeading) {
            dataEntryMenu
        }
        ToolbarItem(placement: .topBarLeading) {
            viewMenu
        }
        ToolbarItem(placement: .topBarLeading) {
            photosToolbarMenu
        }
    }
    //===================
    //FILE HANDLING MENU
    //===================
    private var fileHandlingMenu: some View {
        Menu {
            Button("Save to Text File") {
                let text = dataManager.generateExportText()
                queueExport(.text(text, name: "FamilyData"))
            }
            .disabled(dataManager.membersDictionary.isEmpty)
            Button("Save to a Tree File") {
                do {
                    let members = Array(dataManager.membersDictionary.values)
                    let data = try JSONEncoder().encode(members)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        queueExport(.json(jsonString, name: "FTname.json"))
                    }
                } catch {
                    alertMessage = "Failed to encode JSON: \(error.localizedDescription)"
                    showAlert = true
                }
            }
            .disabled(dataManager.membersDictionary.isEmpty)
            Button("Append from a Tree File") {
                if !isFolderSelected {
                    alertMessage = "Please select a storage folder first (Location → Select Storage Folder…)."
                    showAlert = true
                    return
                }
                // Prevent overlapping presentations
                guard !isPresentingTransition else { return }
                isPresentingTransition = true
                // Guard against re-entry while chooser or file handling is active
                guard !showJSONAppendChooser && !showFileHandling else { return }
                showJSONAppendChooser = true
            }
            .disabled(!isFolderSelected)
            Button("Load from a Tree File") {
                if !isFolderSelected {
                    alertMessage = "Please select a storage folder first (Location → Select Storage Folder…)."
                    showAlert = true
                    return
                }
                // Prevent overlapping presentations
                guard !isPresentingTransition else { return }
                isPresentingTransition = true
                // Guard against re-entry while chooser or file handling is active
                guard !showJSONChooser && !showFileHandling else { return }
                showJSONChooser = true
            }
            .disabled(!isFolderSelected)
        } label: { Text("File Handling") }
        .font(.footnote)
    }
    //================
    //DATA ENTRY MENU
    //================
    private var dataEntryMenu: some View {
        Menu {
            Button("Paste/Parse Bulk Data") { showBulkEditor = true }
            Divider()
            Button("Enter/Edit by Member") {
                originalMembers = FamilyDataManager.shared.membersDictionary
                showIndividualEntry = true
            }
            Divider()
            Button("Clear All Data", role: .destructive) { showDataEntryClearAlert = true }
                .disabled(FamilyDataManager.shared.membersDictionary.isEmpty)
        } label: { Text("Data Entry") }
        .font(.footnote)
    }
    //==============
    //TREE VIEW MENU
    //===============
    private var viewMenu: some View {
        Menu {
            Button {
                if FamilyDataManager.shared.membersDictionary.isEmpty {
                    alertMessage = "No family data. Please add or parse data first"
                    showAlert = true
                } else {
                    showFamilyTree = true
                }
            } label: { Label("Show Family Tree", systemImage: "person.3") }
            .disabled(dataManager.membersDictionary.isEmpty)
        } label: { Text("View") }
        .font(.footnote)
    }
    //===========
    // PHOTO MENU
    //===========
    private var photosToolbarMenu: some View {
        Menu {
            PhotosMenu(
                showGallery: $showGallery,
                showFilteredPhotos: $showFilteredPhotos,
                showAllAttachments: $showAllAttachments,  // ← ADDED BINDING
                showPhotoImporter: $showPhotoImporter,
                showNamePrompt: $showNamePrompt,
                tempNameInput: $tempNameInput,
                filteredNamesForPhotos: $filteredNamesForPhotos,
                alertMessage: $alertMessage,
                showAlert: $showAlert,
                showSuccess: $showSuccess,
                successMessage: $successMessage,
                showResetConfirm: $showResetPhotoIndexConfirm
            )
        } label: { Text("Photos") }
        .disabled(!isFolderSelected || isImportingPhoto)
        .font(.footnote)
        .confirmationDialog(
            "Reset Photo Index?",
            isPresented: $showResetPhotoIndexConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete and Recreate", role: .destructive) {
                guard let folder = resolveFolderURL(showError: true) else {
                    alertMessage = "Please select a storage folder first (Location → Select Storage Folder…)."
                    showAlert = true
                    return
                }
                guard folder.startAccessingSecurityScopedResource() else {
                    alertMessage = "Could not get permission to modify the folder."
                    showAlert = true
                    return
                }
                defer { folder.stopAccessingSecurityScopedResource() }
                do {
                    let idx = try StorageManager.shared.ensurePhotoIndex(in: folder, fileName: "photo-index.json")
                    if FileManager.default.fileExists(atPath: idx.path) {
                        try FileManager.default.removeItem(at: idx)
                    }
                    let recreated = try StorageManager.shared.ensurePhotoIndex(in: folder, fileName: "photo-index.json")
                    let attrs = try? FileManager.default.attributesOfItem(atPath: recreated.path)
                    let fileSize = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                    if fileSize == 0 {
                        try Data("[]".utf8).write(to: recreated, options: .atomic)
                    }
                    successMessage = "Photo index reset."
                    showSuccess = true
                } catch {
                    alertMessage = "Failed to reset photo index: \(error.localizedDescription)"
                    showAlert = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete all photo index entries and recreate an empty index. This cannot be undone.")
        }
    }
    
    // This helper property builds the main view content
    @ViewBuilder
    private var mainViewHierarchy: some View {
        VStack(spacing: 16) {
            Text("Welcome to Family Tree")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .toolbar { mainToolbar }
        .opacity(showFileHandling ? 0 : 1)
    }
    
    @ViewBuilder
    private var contentHost: some View {
        mainViewHierarchy // Call the main view
            .photosPicker(isPresented: $showPhotoImporter, selection: $pickedItem, matching: .images)
            .fileExporter(
                isPresented: showExporterBinding,
                document: exportDoc,
                contentType: exportType,
                defaultFilename: exportName
            ) { result in
                switch result {
                case .success(let url):
                    let folder = url.deletingLastPathComponent()
                    // Don't auto-save this folder, user must pick it
                    // GlobalVariables.shared.selectedFolderURL = folder
                    if url.pathExtension.lowercased() == "json" { GlobalVariables.shared.selectedJSONURL = url }
                    successMessage = "Saved "
                    showSuccess = true
                    FamilyDataManager.shared.isDirty = false
                case .failure(let error):
                    let nsErr = error as NSError
                    if nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSUserCancelledError {
                        break
                    }
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
                globals.exportPayload = .none
                globals.showExporter = false
                exportingNow = false
            }
            .alert("Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK") { }
            } message: {
                Text(successMessage)
            }
            .alert("Clear all in-memory family data?", isPresented: $showDataEntryClearAlert) {
                Button("Clear", role: .destructive) {
                    dataManager.membersDictionary.removeAll()
                    dataManager.focusedMemberId = nil
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes all parsed data from memory. It does not affect files on disk.")
            }
            .onChange(of: globals.showExporter) { oldValue, newValue in
                if newValue == false {
                    globals.exportPayload = .none
                    exportingNow = false
                }
            }
            // FIX: Corrected switch statement to be exhaustive
            .onReceive(globals.$exportPayload) { newValue in
                switch newValue {
                case .none:
                    break
                case .text, .json, .image:
                    prepareExport(for: newValue)
                    guard !exportingNow else { return }
                    exportingNow = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { globals.showExporter = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        if GlobalVariables.shared.showExporter == false && exportingNow {
                            exportingNow = false
                        }
                    }
                }
            }
            .onChange(of: pickedItem) { _, newItem in
                guard let item = newItem, !isImportingPhoto else { return }
                isImportingPhoto = true
                Task {
                    await handlePickedItem(item)
                    await MainActor.run { isImportingPhoto = false }
                }
            }
            .onChange(of: showJSONPicker) { oldValue, newValue in
                if oldValue == true && newValue == false, let url = pendingLoadURL {
                    globals.selectedJSONURL = url
                    pendingFileHandlingCommand = .importLoad
                    showFileHandling = true
                    pendingLoadURL = nil
                }
            }
            // Modified fileImporter handler: offload JSON preview reading to background task to mitigate main-thread stalls
            .fileImporter(
                isPresented: $showJSONFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard !showFileHandling else { return } // already presenting
                    if let url = urls.first {
                        if globals.selectedJSONURL != url {
                            globals.selectedJSONURL = url
                            Task.detached(priority: .utility) {
                                let preview: String
                                do {
                                    let data = try Data(contentsOf: url)
                                    preview = String(data: data, encoding: .utf8) ?? "«binary JSON?»"
                                } catch {
                                    preview = "Failed to read JSON: \(error.localizedDescription)"
                                }
                                await MainActor.run {
                                    globals.openedJSONPreview = String(preview.prefix(2000))
                                }
                            }
                        }
                        pendingFileHandlingCommand = .importLoad
                        if !showFileHandling {
                            showFileHandling = true
                        }
                        // Ensure importer is off to prevent re-presentation
                        showJSONFileImporter = false
                    }
                case .failure(let error):
                    alertMessage = error.localizedDescription
                    showAlert = true
                    // Ensure importer is off in case of failure
                    showJSONFileImporter = false
                }
            }
            .onChange(of: showJSONFileImporter) { old, new in
            }
            .onChange(of: showFileHandling) { old, new in
            }
            .onChange(of: pendingFileHandlingCommand) { old, new in
            }
    }

    var body: some View {
        NavigationStack {
            contentHost
                // === ALL SHEETS AND COVERS MOVED HERE ===
                .sheet(isPresented: $showFolderPicker) {
                    NavigationStack {
                        FolderPickerView { url in
                            // We must start access to get the bookmark
                            guard url.startAccessingSecurityScopedResource() else {
                                alertMessage = "Couldn't access the selected folder. Please try a different location."
                                showAlert = true
                                showFolderPicker = false
                                return
                            }
                            
                            // Defer stopping access
                            defer {
                                url.stopAccessingSecurityScopedResource()
                                print("[ContentView] Stopped security access after getting bookmark.")
                            }
                            
                            do {
                                // 1. Get the bookmark data (the permission)
                                let bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                                
                                // 2. Save this data persistently
                                UserDefaults.standard.set(bookmarkData, forKey: "selectedFolderBookmark")
                                print("[ContentView] Saved FULL folder permission bookmark.")
                                
                                // 3. Set this for immediate use by other functions
                                globals.selectedFolderURL = url
                                
                                // 4. Ensure a photo index exists
                                do {
                                    _ = try StorageManager.shared.ensurePhotoIndex(in: url, fileName: "photo-index.json")
                                } catch {
                                    // Non-blocking
                                }

                            } catch {
                                alertMessage = "Failed to save folder permission: \(error.localizedDescription)"
                                showAlert = true
                                print("[ContentView] Failed to save bookmark: \(error)")
                            }
                            showFolderPicker = false
                        }
                        .navigationTitle("Select Folder")
                    }
                }
                .sheet(isPresented: $showJSONChooser) {
                    NavigationStack {
                        JSONFileChooserView(
                            onPickJSON: { url in
                                showJSONChooser = false
                                globals.selectedJSONURL = url
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    pendingFileHandlingCommand = .importLoad
                                    if !showFileHandling {
                                        showFileHandling = true
                                    }
                                }
                                Task.detached(priority: .utility) {
                                    if let data = try? Data(contentsOf: url),
                                        let preview = String(data: data, encoding: .utf8) {
                                        let clipped = String(preview.prefix(2000))
                                        await MainActor.run {
                                            globals.openedJSONPreview = clipped
                                        }
                                    } else {
                                        await MainActor.run {
                                            globals.openedJSONPreview = "Preview unavailable (file may still be downloading or unreadable)."
                                        }
                                    }
                                }
                            },
                            onCancel: {
                                showJSONChooser = false
                            }
                        )
                        .onDisappear { isPresentingTransition = false }
                        .navigationTitle("Choose Tree JSON")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showJSONChooser = false }
                            }
                        }
                    }
                }
                .sheet(isPresented: $showJSONAppendChooser) {
                    NavigationStack {
                        JSONFileChooserView(
                            onPickJSON: { url in
                                showJSONAppendChooser = false
                                globals.selectedJSONURL = url
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    pendingFileHandlingCommand = .importAppend
                                    if !showFileHandling { showFileHandling = true }
                                }
                                Task.detached(priority: .utility) {
                                    if let data = try? Data(contentsOf: url),
                                        let preview = String(data: data, encoding: .utf8) {
                                        await MainActor.run {
                                            globals.openedJSONPreview = String(preview.prefix(2000))
                                        }
                                    }
                                }
                            },
                            onCancel: {
                                showJSONAppendChooser = false
                            }
                        )
                        .onDisappear { isPresentingTransition = false }
                        .navigationTitle("Choose Tree JSON to Append")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showJSONAppendChooser = false }
                            }
                        }
                    }
                }
                // ========== FINAL STABLE PASS: RAW BOOKMARK DATA IS USED ==========
                .sheet(isPresented: $showGallery) {
                    // Get the raw bookmark data
                    if let bookmark = UserDefaults.standard.data(forKey: "selectedFolderBookmark") {
                        if #available(iOS 16.0, *) {
                            PhotoBrowserView(
                                folderBookmark: bookmark // Pass the bookmark DATA
                            )
                        } else {
                            Text("Requires iOS 16.0 or later.")
                                .padding()
                        }
                    } else {
                        // This will now show if the bookmark is missing.
                        VStack {
                            Text("Could not get permission for the folder.")
                                .font(.headline)
                                .padding()
                            Text("Please go to 'Location' and re-select your folder.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                // ========== FINAL STABLE PASS: RAW BOOKMARK DATA IS USED ==========
                .sheet(isPresented: $showFilteredPhotos) {
                    // Get the raw bookmark data
                    if let bookmark = UserDefaults.standard.data(forKey: "selectedFolderBookmark") {
                        
                        if #available(iOS 16.0, *) {
                            FilteredPhotoBrowserView(
                                folderBookmark: bookmark, // Pass the bookmark DATA
                                filterNames: filteredNamesForPhotos
                            )
                        } else {
                            Text("Requires iOS 16.0 or later.")
                                .padding()
                        }
                    } else {
                        // This will now show if the bookmark is missing.
                        VStack {
                            Text("Could not get permission for the folder.")
                                .font(.headline)
                                .padding()
                            Text("Please go to 'Location' and re-select your folder.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                // ========== NEW: ATTACHMENTS BROWSER SHEET ==========
                .sheet(isPresented: $showAllAttachments) {
                    if let bookmark = UserDefaults.standard.data(forKey: "selectedFolderBookmark") {
                        AttachmentsBrowserView(folderBookmark: bookmark)
                    } else {
                        VStack(spacing: 20) {
                            Text("No Storage Folder Selected")
                                .font(.headline)
                            Text("Please select a folder in Location menu.")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                            Button("OK") {
                                showAllAttachments = false
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }
                }
                .fullScreenCover(isPresented: $showFamilyTree) {
                    NavigationStack {
                        FamilyTreeView()
                            .navigationTitle("Family Tree")
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { showFamilyTree = false }
                                }
                            }
                    }
                }
                .fullScreenCover(isPresented: $showFileHandling) {
                    NavigationStack {
                        if let cmd = pendingFileHandlingCommand {
                            FileHandlingView(command: cmd, preselectedURL: globals.selectedJSONURL)
                                .navigationTitle("File Handling")
                                .toolbar {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        Button("Done") {
                                            showFileHandling = false
                                            pendingFileHandlingCommand = nil
                                        }
                                    }
                                }
                        } else {
                            Text("Preparing…")
                                .navigationTitle("File Handling")
                                .toolbar {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        Button("Done") { showFileHandling = false }
                                    }
                                }
                        }
                    }
                }
                .sheet(isPresented: $showIndividualEntry) {
                    NavigationStack {
                        FamilyDataInputView()
                            .navigationTitle("Enter/Edit By Member")
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { showIndividualEntry = false }
                                }
                            }
                    }
                }
                .sheet(isPresented: $showBulkEditor) {
                    BulkEditorSheet(
                        isPresented: $showBulkEditor,
                        bulkText: $bulkText,
                        showConfirmation: $showConfirmation,
                        showSuccess: $showSuccess,
                        successMessage: $successMessage
                    )
                }
                // Modified to dismiss keyboard before showing photo importer to avoid layout conflicts
                .sheet(isPresented: $showNamePrompt) {
                    NamePromptSheet(
                        isPresented: $showNamePrompt,
                        tempNameInput: $tempNameInput,
                        onConfirm: { name in
                            pendingPhotoName = name
                            // Dismiss any active keyboard before presenting PhotosPicker
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                showPhotoImporter = true
                            }
                        },
                        existingNames: {
                            if let idx = try? currentPhotoIndexURL(), let names = try? readIndexNames(from: idx) {
                                return names
                            } else {
                                return []
                            }
                        }()
                    )
                }
        }
    }
}

#Preview {
    ContentView()
}

