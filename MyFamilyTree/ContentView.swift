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
                    //Do not show the whole path to the user
                    //successMessage = "Imported “\(result.displayName)” → \(result.savedURL.lastPathComponent)"
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
        }
        //=========MAIN MENU ENTRY===========
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                PhotosMenu(
                    showFolderPicker: $showFolderPicker,
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
            }

            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Paste/Parse Bulk Data") { showBulkEditor = true }
                    Divider()
                    Button("Individual Entry") {
                        originalMembers = FamilyDataManager.shared.membersDictionary
                        showIndividualEntry = true
                    }
                    Divider()
                    Button("Clear All Data", role: .destructive) { showDataEntryClearAlert = true }
                        .disabled(FamilyDataManager.shared.membersDictionary.isEmpty)
                } label: { Text("Data Entry") }
                .font(.footnote)
            }
            
            ToolbarItem(placement: .topBarLeading) {
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
            
            ToolbarItem(placement: .topBarLeading) {
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
                        pendingFileHandlingCommand = .importAppend
                        showFileHandling = true
                    }
                    Button("Load from a Tree File") {
                        pendingFileHandlingCommand = .importLoad
                        showFileHandling = true
                    }
                } label: { Text("File Handling") }
                .font(.footnote)
            }
        }
        
        
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
            BulkEditorSheet(
                isPresented: $showBulkEditor,
                bulkText: $bulkText,
                showConfirmation: $showConfirmation,
                showSuccess: $showSuccess,
                successMessage: $successMessage
            )
        }
        ///This will call the Name Prompt Sheet . I modified it not to allow duplicate names
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

    var body: some View {
        NavigationStack {
            contentHost
        }
    }
}

#Preview {
    ContentView()
}

