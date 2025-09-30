//
//  ContentView.swift
//  SwiftTreeTwo
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
    
    // New state flags to drive JSON importers directly
    // Removed:
    // @State private var showJSONPickerForLoad = false
    // @State private var showJSONPickerForAppend = false
    @State private var showUIKitPickerForLoad = false
    @State private var showUIKitPickerForAppend = false
    
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
    // Removed showClearAlert as per instructions
    // @State private var showClearAlert = false
    @State private var entryMode: EntryMode = .bulk
    
    @FocusState private var bulkEditorFocused: Bool
    
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
    
    
    enum EntryMode: String, CaseIterable {
        case bulk = "Bulk"
        case individual = "Individual"
    }
    
    // Helper to queue an export (handled by onReceive)
    private func queueExport(_ payload: ExportPayload) {
        globals.exportPayload = payload
    }
    
    // Auto-unique filenames
    private func stamped(_ base: String, ext: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        return "\(base)-\(fmt.string(from: Date())).\(ext)"
    }
    
    // New helpers for JSON loading and validation
    private func loadMembers(from url: URL) throws -> [FamilyMember] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([FamilyMember].self, from: data)
    }

    private func isLikelyJSON(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "json"
    }
    
    private func readIndexNames(from indexURL: URL) throws -> Set<String> {
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
        
        VStack(spacing: 16) {
            Text("Welcome to Family Tree")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        /*=====No Need to show the title
        .navigationTitle("Family Tree")
        .navigationBarTitleDisplayMode(.inline)
        */
        .photosPicker(isPresented: $showPhotoImporter, selection: $pickedItem, matching: .images)
        
        // Attach the exporter directly to this view
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
                successMessage = "Saved to \(folderDisplay)/\(url.lastPathComponent)"
                showSuccess = true
            case .failure(let error):
                let nsErr = error as NSError
                if nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSUserCancelledError {
                    // User cancelled — no alert
                    break
                }
                alertMessage = error.localizedDescription
                showAlert = true
            }
            // Reset for future presentations
            globals.exportPayload = .none
            globals.showExporter = false
            exportingNow = false
        }
        
        // Error + success alerts
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
        // New alert for clearing data via Data Entry menu
        .alert("Clear all in-memory family data?", isPresented: $showDataEntryClearAlert) {
            Button("Clear", role: .destructive) {
                dataManager.membersDictionary.removeAll()
                dataManager.focusedMemberId = nil
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes all parsed data from memory. It does not affect files on disk.")
        }
        
        // Keep debounce healthy after close
        //Set the exportingNow to false to allow export in the .onReceive
        //Detects the change of the showExporter
        .onChange(of: globals.showExporter) { oldValue, newValue in
            //print("🔔 showExporter:", oldValue, "→", newValue)
            if newValue == false {
                globals.exportPayload = .none
                exportingNow = false
            }
        }
        //I setglobals.exportPayload to set the appropriate function as in the following code
        // React to payload changes → prepare doc and present
        // Runs a closure wnenever there is a newValue
        .onReceive(globals.$exportPayload) { newValue in
            //No need now to print to the console
            // print("📦 exportPayload →", String(describing: newValue))
            switch newValue {
            case .none:
                break
            //Text file
            case .text(let s, let name):
                exportDoc = TempExportDocument(data: Data(s.utf8))
                exportType = .plainText
                exportName = name.isEmpty ? stamped("READ_ME", ext: "txt") : name
            //JSON file
            case .json(let jsonString, let name):
                exportDoc = TempExportDocument(data: Data(jsonString.utf8))
                exportType = .json
                let final = name.isEmpty ? stamped("database", ext: "json") : (name.hasSuffix(".json") ? name : "\(name).json")
                exportName = final
            //Image file
            case .image(let bytes, let name, let type):
                exportDoc = TempExportDocument(data: bytes)
                exportType = type
                exportName = name
            }
            if case .none = newValue {
                // nothing to do
            } else {
                guard !exportingNow else { return }
                exportingNow = true
                //Set exportingNow to cancel triggering the export twice before the first one ends
                DispatchQueue.main.async {
                    globals.showExporter = true
                }
                // Failsafe unlock if sheet doesn’t appear (simulator quirk)
                // Wait 2.5 seconds then allow exporting again
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if GlobalVariables.shared.showExporter == false && exportingNow {
                        exportingNow = false
                    }
                }
            }
        }
        
        // Photos import handler (now thin and simple)
        .onChange(of: pickedItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
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
                    globals.selectedJSONURL = result.indexURL  // in case it was created
                    successMessage = "Imported “\(result.displayName)” → \(result.savedURL.lastPathComponent)"
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
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                HStack(spacing: 20) {
                    // PHOTOS MENU
                    Menu {
                        if let url = globals.selectedFolderURL {
                            Text("Folder: \(url.lastPathComponent)").font(.caption2)
                        } else {
                            Text("Folder: none").foregroundColor(.secondary).font(.caption2)
                        }
                        Divider()

                        Button("Select Storage Folder…") { showFolderPicker = true }

                        Button("Create Photo Index in Folder") {
                            guard let folder = globals.selectedFolderURL else {
                                alertMessage = "Please select a storage folder first."
                                showAlert = true
                                return
                            }
                            do {
                                let indexURL = folder.appendingPathComponent("photo-index.json")
                                if FileManager.default.fileExists(atPath: indexURL.path) {
                                    throw CocoaError(.fileWriteFileExists)
                                }
                                let url = try StorageManager.shared.ensurePhotoIndex(in: folder, fileName: "photo-index.json")
                                globals.selectedJSONURL = url
                                successMessage = "Photo index created at “\(url.lastPathComponent)”."
                                showSuccess = true
                            } catch {
                                let nsErr = error as NSError
                                if nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSFileWriteFileExistsError {
                                    alertMessage = "A photo index already exists in the selected folder."
                                } else {
                                    alertMessage = error.localizedDescription
                                }
                                showAlert = true
                            }
                        }
                        .disabled(globals.selectedFolderURL == nil)
                        .help(globals.selectedFolderURL == nil ? "Select a storage folder first" : "")

                        Divider()

                        Button("Import a Photo …") {
                            guard globals.selectedFolderURL != nil else {
                                alertMessage = "Select a storage folder first."
                                showAlert = true
                                return
                            }
                            tempNameInput = ""
                            showNamePrompt = true
                        }
                        .disabled(globals.selectedFolderURL == nil)
                        .help(globals.selectedFolderURL == nil ? "Select a storage folder first" : "")

                        Button("Browse All Photos") {
                            if let folder = globals.selectedFolderURL {
                                if globals.selectedJSONURL == nil {
                                    do {
                                        let url = try StorageManager.shared.ensurePhotoIndex(in: folder, fileName: "photo-index.json")
                                        globals.selectedJSONURL = url
                                    } catch {
                                        alertMessage = "Failed to prepare photo index: \(error.localizedDescription)"
                                        showAlert = true
                                        return
                                    }
                                }
                                guard globals.selectedJSONURL != nil else {
                                    alertMessage = "Select a storage folder and photo index first."
                                    showAlert = true
                                    return
                                }
                                showGallery = true
                            } else {
                                alertMessage = "Select a storage folder first."
                                showAlert = true
                            }
                        }
                        .disabled(globals.selectedFolderURL == nil)
                        .help(globals.selectedFolderURL == nil ? "Select a storage folder first" : "")

                        Button("Browse Tree Photos") {
                            // Ensure we have family data
                            if FamilyDataManager.shared.membersDictionary.isEmpty {
                                alertMessage = "No family data loaded. Please add or parse data first."
                                showAlert = true
                                return
                            }
                            // Ensure folder and index are selected
                            guard let folder = globals.selectedFolderURL else {
                                alertMessage = "Select a storage folder first (Photos menu)."
                                showAlert = true
                                return
                            }
                            if globals.selectedJSONURL == nil {
                                do {
                                    let url = try StorageManager.shared.ensurePhotoIndex(in: folder, fileName: "photo-index.json")
                                    globals.selectedJSONURL = url
                                } catch {
                                    alertMessage = "Failed to prepare photo index: \(error.localizedDescription)"
                                    showAlert = true
                                    return
                                }
                            }
                            guard let _ = globals.selectedJSONURL else {
                                alertMessage = "Select a storage folder and photo index first (Photos menu)."
                                showAlert = true
                                return
                            }
                            // Compute visible names from current tree
                            let manager = FamilyDataManager.shared
                            let groups: [LevelGroup]
                            if let focus = manager.focusedMemberId {
                                groups = manager.getConnectedFamilyOf(memberId: focus)
                            } else {
                                groups = manager.getAllLevels()
                            }
                            let names = groups.flatMap { $0.members.map { $0.name } }
                            filteredNamesForPhotos = Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

                            if filteredNamesForPhotos.isEmpty {
                                alertMessage = "No visible names in the current tree."
                                showAlert = true
                                return
                            }
                            // Validate index contents
                            if let idxURL = globals.selectedJSONURL {
                                do {
                                    let indexNames = try readIndexNames(from: idxURL)
                                    if indexNames.isEmpty {
                                        alertMessage = "No photos found in the photo index for folder \"\(folder.lastPathComponent)\".\nUse Photos → Import a Photo to add photos for your tree members, then try again."
                                        showAlert = true
                                        return
                                    }
                                    let visible = Set(filteredNamesForPhotos)
                                    let intersection = visible.intersection(indexNames)
                                    if intersection.isEmpty {
                                        alertMessage = "None of the visible names are present in the photo index.\nNames: \(filteredNamesForPhotos.joined(separator: ", "))"
                                        showAlert = true
                                        return
                                    }
                                } catch {
                                    alertMessage = "Failed to read photo index: \(error.localizedDescription)"
                                    showAlert = true
                                    return
                                }
                            }
                            showFilteredPhotos = true
                        }
                        .disabled(globals.selectedFolderURL == nil || dataManager.membersDictionary.isEmpty)
                        .help(globals.selectedFolderURL == nil ? "Select a storage folder first" : (dataManager.membersDictionary.isEmpty ? "Add or parse family data first" : ""))
                    } label: {
                        Text("Photos")
                    }
                    .font(.footnote)

                    // DATA ENTRY MENU
                    Menu {
                        Button("Paste/Parse Bulk Data") {
                            showBulkEditor = true
                        }
                        Divider()
                        Button("Individual Entry") {
                            originalMembers = FamilyDataManager.shared.membersDictionary
                            showIndividualEntry = true
                        }
                        Divider()
                        Button("Clear All Data", role: .destructive) {
                            showDataEntryClearAlert = true
                        }
                        .disabled(FamilyDataManager.shared.membersDictionary.isEmpty)
                    } label: {
                        Text("Data Entry")
                    }
                    .font(.footnote)

                    // VIEW MENU
                    Menu {
                        Button {
                            if FamilyDataManager.shared.membersDictionary.isEmpty {
                                alertMessage = "No family data loaded. Please add or parse data first."
                                showAlert = true
                            } else {
                                showFamilyTree = true
                            }
                        } label: {
                            Label("Show Family Tree", systemImage: "person.3")
                        }
                        .disabled(dataManager.membersDictionary.isEmpty)
                        .help(dataManager.membersDictionary.isEmpty ? "Add or parse family data first" : "")
                    } label: {
                        Text("View")
                    }
                    .font(.footnote)

                    // FILE HANDLING MENU
                    Menu {
                        Button("Save to Text File") {
                            let text = dataManager.generateExportText()
                            queueExport(.text(text, name: "FamilyData"))
                        }
                        .disabled(dataManager.membersDictionary.isEmpty)
                        .help(dataManager.membersDictionary.isEmpty ? "Add or parse family data first" : "")

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
                        .help(dataManager.membersDictionary.isEmpty ? "Add or parse family data first" : "")

                        Button("Append from JSON file") {
                            // Close other sheets if any
                            showGallery = false
                            showFilteredPhotos = false
                            showFileHandling = false
                            showFolderPicker = false
                            showJSONPicker = false
                            // Present UIKit document picker
                            DispatchQueue.main.async { showUIKitPickerForAppend = true }
                        }
                        Button("Load from a Tree File") {
                            // Close other sheets if any
                            showGallery = false
                            showFilteredPhotos = false
                            showFileHandling = false
                            showFolderPicker = false
                            showJSONPicker = false
                            // Present UIKit document picker
                            DispatchQueue.main.async { showUIKitPickerForLoad = true }
                        }
                    } label: {
                        Text("File Handling")
                    }
                    .font(.footnote)
                }
            }
        }
        
        // Removed old SwiftUI .fileImporter modifiers for showJSONPickerForLoad and showJSONPickerForAppend
        
        //=========
        // SHEETS
        //=========
        /* A,.sheet is the SwiftUI way to present modals: you bind it to some piece of state, and when that state indicates presentation, SwiftUI shows the sheet and manages its lifecycle.
            If true it will show the sheet , when it is false it will dismiss the sheet
        */
        .sheet(isPresented: $showFolderPicker) {
            NavigationStack {
                FolderPickerView { url in
                    if url.startAccessingSecurityScopedResource() {
                        globals.selectedFolderURL = url
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
        .sheet(isPresented: $showJSONPicker) {
            NavigationStack {
                JSONPickerView { url in
                    globals.selectedJSONURL = url
                    do {
                        let data = try Data(contentsOf: url)
                        let preview = String(data: data, encoding: .utf8) ?? "«binary JSON?»"
                        globals.openedJSONPreview = String(preview.prefix(2000))
                    } catch {
                        globals.openedJSONPreview = "Failed to read JSON: \(error.localizedDescription)"
                    }
                    showJSONPicker = false
                }
                .navigationTitle("Open JSON")
            }
        }
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
        .sheet(isPresented: $showFileHandling) {
            NavigationStack {
                FileHandlingView(command: pendingFileHandlingCommand)
                    .navigationTitle("File Handling")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showFileHandling = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showIndividualEntry) {
            NavigationStack {
                FamilyDataInputView()
                    .navigationTitle("Individual Entry")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                // Keep edits as-is
                                showIndividualEntry = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showBulkEditor) {
            NavigationStack {
                VStack(spacing: 12) {
                    Text("Paste Bulk Data")
                        .font(.headline)

                    // SHOW THE TEXT EDITOR
                    TextEditor(text: $bulkText)
                        .focused($bulkEditorFocused)
                        .padding(8)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .frame(minHeight: 220)
                }
                .padding()
                .onAppear { bulkEditorFocused = false }
                .navigationTitle("Bulk Editor")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Parse") {
                            showConfirmation = true
                        }
                        Button("Done") {
                            bulkText = ""
                            showBulkEditor = false
                        }
                    }
                }
                .alert("Parse Bulk Data?", isPresented: $showConfirmation) {
                    // why do i need this button ??????
                    // Button("Cancel", role: .cancel) { }
                    Button("Parse", role: .destructive) {
                        FamilyDataInputView.parseBulkInput(bulkText)
                        successMessage = "Bulk data parsed."
                        showSuccess = true
                        bulkText = ""
                        // Keep the editor open; do not dismiss here.
                    }
                } message: {
                    Text("This will process the pasted text.")
                }
                // Removed alert for clearing data here as per instructions
            }
        }
        .sheet(isPresented: $showNamePrompt) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("Select the photo owner")
                        .font(.headline)
                    TextField("Person's name", text: $tempNameInput)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    HStack {
                        Button("Cancel", role: .cancel) {
                            showNamePrompt = false
                        }
                        Spacer()
                        Button("Import") {
                            pendingPhotoName = tempNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            showNamePrompt = false
                            // proceed to Photos picker
                            showPhotoImporter = true
                        }
                        .disabled(tempNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)
                }
                .padding()
                .navigationTitle("Name for Photo")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Import") {
                            pendingPhotoName = tempNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            showNamePrompt = false
                            showPhotoImporter = true
                        }
                        .disabled(tempNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        
        // MARK: Consistent iPad view
        .navigationViewStyle(StackNavigationViewStyle())
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
