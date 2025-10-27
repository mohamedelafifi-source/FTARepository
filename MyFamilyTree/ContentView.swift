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
    /*
    What is @ObservedObject: A SwiftUI property wrapper that lets a view subscribe to an external observable object (an instance of a class that conforms to ObservableObject).
    • Why it’s used: When any @Published property inside the observed object changes, SwiftUI will re-render the parts of the view that depend on it.
    • How it works:
       • Your object class adopts ObservableObject.
       • Properties you want to trigger UI updates are marked with @Published.
    */
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
    
    @State private var pendingPhotoName: String = ""   // optional; set name before importing
    
    @State private var bulkText = ""
    @State private var showBulkEditor = false
    @State private var showIndividualEntry = false
    @State private var showFamilyTree = false
    @State private var showFileHandling = false
    
    @State private var originalMembers: [String: FamilyMember] = [:]
    
    @State private var showConfirmation = false
    @State private var entryMode: EntryMode = .bulk
    
    // Exporter state
    @State private var exportingNow = false
    @State private var exportDoc = TempExportDocument(data: Data())
    @State private var exportType: UTType = .plainText
    @State private var exportName: String = "Export"
    
    // Alerts
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showSuccess = false
    @State private var successMessage = ""
    
    // New state variables for filtered photo view
    @State private var showFilteredPhotos = false
    @State private var filteredNamesForPhotos: [String] = []
    @State private var isHandlingJSONPick = false
    
    @State private var pendingLoadURL: URL? = nil
    
    // Added state for system file importer for JSON tree file loading
    @State private var showJSONFileImporter = false
    
    enum EntryMode: String, CaseIterable {
        case bulk = "Bulk"
        case individual = "Individual"
    }
    
    // Display helper for the Location menu path line
    fileprivate var folderPathDisplay: String {
        if let url = globals.selectedFolderURL {
            return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        } else {
            return "None selected"
        }
    }
    
    // Simple flag for Location menu state (kept out of the view builder)
    fileprivate var isFolderSelected: Bool {
        globals.selectedFolderURL != nil
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
        guard let folder = globals.selectedFolderURL else {
            alertMessage = "Please select a storage folder first (Location → Select Storage Folder…)."
            showAlert = true
            return
        }
        do {
            let result = try await PhotoImportService.importFromPhotos(
                item: item,
                folderURL: folder,
                currentIndexURL: globals.selectedJSONURL,
                personName: pendingPhotoName
            )
            globals.selectedJSONURL = result.indexURL
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
                if globals.selectedFolderURL == nil {
                    alertMessage = "Please select a storage folder first (Location → Select Storage Folder…)."
                    showAlert = true
                    return
                }
                pendingFileHandlingCommand = .importAppend
            }
            .disabled(globals.selectedFolderURL == nil)
            Button("Load from a Tree File") {
                print("DEBUG Load button tapped, importer:", showJSONFileImporter, "fileHandling:", showFileHandling, "time:", Date())
                if globals.selectedFolderURL == nil {
                    alertMessage = "Please select a storage folder first (Location → Select Storage Folder…)."
                    showAlert = true
                    return
                }
                // Guard against re-entry while importer or file handling is active
                guard !showJSONFileImporter && !showFileHandling else { return }
                // Use system file importer to choose any JSON file to load
                showJSONFileImporter = true
            }
            .disabled(globals.selectedFolderURL == nil)
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
        PhotosMenu(
            showGallery: $showGallery,
            showFilteredPhotos: $showFilteredPhotos,
            showPhotoImporter: $showPhotoImporter,
            showNamePrompt: $showNamePrompt,
            tempNameInput: $tempNameInput,
            filteredNamesForPhotos: $filteredNamesForPhotos,
            alertMessage: $alertMessage,
            showAlert: $showAlert,
            showSuccess: $showSuccess,
            successMessage: $successMessage
        )
        .disabled(globals.selectedFolderURL == nil)
    }
    
    private func attachSheets<V: View>(to view: V) -> some View {
        view
            .sheet(isPresented: $showFolderPicker) {
                NavigationStack {
                    FolderPickerView { url in
                        //SET THE GLOBAL FOLDER LOCATION HERE. IT SHOULD BE SET GLOBALLY
                        if url.startAccessingSecurityScopedResource() {
                            globals.selectedFolderURL = url
                            // Ensure a photo index exists and set selectedJSONURL so File Handling works immediately
                            do {
                                let idx = try StorageManager.shared.ensurePhotoIndex(in: url, fileName: "photo-index.json")
                                globals.selectedJSONURL = idx
                            } catch {
                                // Non-blocking: log or show a soft alert if desired
                            }
                            showFolderPicker = false
                        } else {
                            alertMessage = "Couldn’t access the selected folder. Please try a different location."
                            showAlert = true
                            showFolderPicker = false
                        }
                    }
                    .navigationTitle("Select Folder")
                }
            }
            // Temporarily disabled JSON picker sheet to avoid interference with Load flow
            .background(
                Group {
                    if false {
                        EmptyView()
                    }
                }
            )
            .sheet(isPresented: $showGallery) {
                if let folder = globals.selectedFolderURL, let idx = globals.selectedJSONURL {
                    if #available(iOS 16.0, *) {
                        PhotoBrowserView(folderURL: folder, indexURL: idx)
                    } else {
                        Text("Requires iOS 16.0 or later.")
                            .padding()
                    }
                } else {
                    ImagesListView()
                }
            }
            .sheet(isPresented: $showFilteredPhotos) {
                if let folder = globals.selectedFolderURL, let idx = globals.selectedJSONURL {
                    if #available(iOS 16.0, *) {
                        FilteredPhotoBrowserView(folderURL: folder, indexURL: idx, filterNames: filteredNamesForPhotos)
                    } else {
                        Text("Requires iOS 16.0 or later.")
                            .padding()
                    }
                } else {
                    Text("Select a storage folder and photo index first.")
                        .padding()
                }
            }
            .sheet(isPresented: $showFamilyTree) {
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
                        // Fallback if presentation occurs before command is ready
                        Text("Preparing…")
                            .onAppear {
                                // print removed
                            }
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
            .sheet(isPresented: $showNamePrompt) {
                NamePromptSheet(
                    isPresented: $showNamePrompt,
                    tempNameInput: $tempNameInput,
                    onConfirm: { name in
                        pendingPhotoName = name
                        showPhotoImporter = true
                    },
                    existingNames: {
                        if let idx = globals.selectedJSONURL, let names = try? readIndexNames(from: idx) {
                            return names
                        } else {
                            return []
                        }
                    }()
                )
            }
    }
    
    /*
     What is @ViewBuilder: A special attribute used by SwiftUI to allow multiple child views to be returned from a function or closure, while still appearing like a single expression.
     • Why it’s used: It lets you write “if/else” and multiple views inline without manually wrapping them in containers or arrays.
     • How it works:
        • The compiler translates multiple child expressions into a single composed view using the ViewBuilder rules.
        • You can use control flow (if, switch) to conditionally include views.
        • It’s used in SwiftUI APIs like body, VStack content closures, and custom view-returning functions.
     */
    @ViewBuilder
    private var contentHost: some View {
        let base = VStack(spacing: 16) {
            Text("Welcome to Family Tree")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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
                let folderDisplay = folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                //No Need to show the path
                //successMessage = "Saved to \(folderDisplay)/\(url.lastPathComponent)"
                successMessage = "Saved "
                showSuccess = true
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
            Button("Copy Path") {
                UIPasteboard.general.string = successMessage
            }
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
        .onReceive(globals.$exportPayload) { newValue in
            switch newValue {
            case .none:
                break
            default:
                prepareExport(for: newValue)
                guard !exportingNow else { return }
                exportingNow = true
                DispatchQueue.main.async { globals.showExporter = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if GlobalVariables.shared.showExporter == false && exportingNow {
                        exportingNow = false
                    }
                }
            }
        }
        .onChange(of: pickedItem) { _, newItem in
            guard let item = newItem else { return }
            Task { await handlePickedItem(item) }
        }
        /*
        Removed automatic presentation of FileHandlingView on pendingFileHandlingCommand change:
        .onChange(of: pendingFileHandlingCommand) { _, newValue in
            if newValue != nil {
                // print removed
                showFileHandling = true
            }
        }
        */
        .onChange(of: showJSONPicker) { oldValue, newValue in
            // When the JSON picker is dismissed and we have a URL, proceed to load
            if oldValue == true && newValue == false, let url = pendingLoadURL {
                globals.selectedJSONURL = url
                pendingFileHandlingCommand = .importLoad
                showFileHandling = true
                pendingLoadURL = nil
            }
        }
        .fileImporter(
            isPresented: $showJSONFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            print("DEBUG importer result:", result, "time:", Date())
            switch result {
            case .success(let urls):
                guard !showFileHandling else { return } // already presenting
                if let url = urls.first {
                    if globals.selectedJSONURL != url {
                        globals.selectedJSONURL = url
                        do {
                            let data = try Data(contentsOf: url)
                            let preview = String(data: data, encoding: .utf8) ?? "«binary JSON?»"
                            globals.openedJSONPreview = String(preview.prefix(2000))
                        } catch {
                            globals.openedJSONPreview = "Failed to read JSON: \(error.localizedDescription)"
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
            print("DEBUG showJSONFileImporter:", old, "->", new, "time:", Date())
        }
        .onChange(of: showFileHandling) { old, new in
            print("DEBUG showFileHandling:", old, "->", new, "time:", Date())
        }
        .onChange(of: pendingFileHandlingCommand) { old, new in
            print("DEBUG pendingFileHandlingCommand:", String(describing: old), "->", String(describing: new), "time:", Date())
        }
        .toolbar { mainToolbar }

        attachSheets(to: base)
    }

    var body: some View {
        NavigationStack {
            contentHost
        }
    }
}

#Preview {
    ContentView()
}

