//
//  FamilyTreeFileHandling.swift
//  MyFamilyTree
//
//  Created by Mohamed El Afifi on 9/30/25.
//


import Foundation
import SwiftUI
import UniformTypeIdentifiers


// MARK: - Document Types

enum ImportAction {
    case load
    case append
}

enum FileHandlingCommand {
    case exportText
    case exportJSON
    case importAppend
    case importLoad
}

struct FamilyDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }
    
    var members: [FamilyMember]
    
    init(members: [FamilyMember]) {
        self.members = members
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.members = try JSONDecoder().decode([FamilyMember].self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(members)
        return FileWrapper(regularFileWithContents: data)
    }
}

struct TextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    
    var text: String
    
    init(text: String) {
        self.text = text
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadUnknown)
        }
        self.text = string
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: text.data(using: .utf8)!)
    }
}


// MARK: - Main View

struct FileHandlingView: View {
    var command: FileHandlingCommand? = nil
    var preselectedURL: URL? = nil
    @ObservedObject var manager = FamilyDataManager.shared
    
    @State private var isExportingJSON = false
    @State private var isExportingTextFile = false
    @State private var isImporting = false
    @State private var importAction: ImportAction? = nil
    @State private var alertMessage = ""
    @State private var showingAlert = false
    
    var body: some View {
        VStack(spacing: 12) {
            Text("File Handling")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Use the toolbar menu in Content View to perform file actions.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .fileExporter(
            isPresented: $isExportingTextFile,
            document: TextDocument(text: manager.generateExportText()),
            contentType: .plainText,
            defaultFilename: "FamilyData"
        ) { result in
            handleExportResult(result)
        }
        .fileExporter(
            isPresented: $isExportingJSON,
            document: FamilyDataDocument(members: Array(manager.membersDictionary.values)),
            contentType: .json,
            defaultFilename: "FTname.json"
        ) { result in
            handleExportResult(result)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json]
        ) { result in
            guard let action = self.importAction else { return }
            switch action {
            case .load:
                processImportedFile(result, isAppending: false)
            case .append:
                processImportedFile(result, isAppending: true)
            }
            self.importAction = nil
        }
        .alert(alertMessage, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        }
        .onAppear {
            guard let command else { return }
            DispatchQueue.main.async {
                switch command {
                case .exportText:
                    isExportingTextFile = true
                case .exportJSON:
                    isExportingJSON = true
                case .importAppend:
                    importAction = .append
                    isImporting = true
                case .importLoad:
                    if let url = preselectedURL {
                        // Load immediately without showing a picker
                        processImportedFile(.success(url), isAppending: false)
                    } else {
                        // No preselected URL; do nothing (ContentView should provide it)
                        break
                    }
                }
            }
        }
        .onDisappear {
        }
    }
    
    // MARK: - Helper Functions
    
    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(_):
            manager.isDirty = false
            manager.focusedMemberId = nil
            alertMessage = "Successfully saved "
            showingAlert = true
        case .failure(let error):
            alertMessage = "Error saving file: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    private func processImportedFile(_ result: Result<URL, Error>, isAppending: Bool) {
        switch result {
        case .success(let url):
            
            let started = url.startAccessingSecurityScopedResource()
            guard started else {
                alertMessage = "Access to the selected file was denied."
                showingAlert = true
                return
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let importedMembers = try decoder.decode([FamilyMember].self, from: data)
                let count = importedMembers.count
                
                DispatchQueue.main.async {
                    if isAppending {
                        // Build a temporary id-keyed map from current dictionary to merge by stable id
                        var currentByID: [UUID: FamilyMember] = [:]
                        for existing in manager.membersDictionary.values {
                            currentByID[existing.id] = existing
                        }
                        // Merge imported members by id
                        for member in importedMembers {
                            if var existing = currentByID[member.id] {
                                // Merge relationships by names (current schema), deduping entries
                                existing.parents = Array(Set(existing.parents).union(member.parents)).sorted()
                                existing.spouses = Array(Set(existing.spouses).union(member.spouses)).sorted()
                                existing.children = Array(Set(existing.children).union(member.children)).sorted()
                                existing.siblings = Array(Set(existing.siblings).union(member.siblings)).sorted()
                                // Prefer the imported name if it differs (or keep existing.name if you prefer)
                                existing.name = member.name
                                currentByID[member.id] = existing
                            } else {
                                currentByID[member.id] = member
                            }
                        }
                        // Rebuild name-keyed dictionary from id-keyed map
                        manager.membersDictionary.removeAll()
                        for m in currentByID.values {
                            manager.membersDictionary[m.name] = m
                        }
                        alertMessage = "Successfully appended \(count) member(s)."
                    } else {
                        // Load: replace entirely, but deduplicate by id first
                        var byID: [UUID: FamilyMember] = [:]
                        for m in importedMembers {
                            byID[m.id] = m // last one wins for same id
                        }
                        manager.membersDictionary.removeAll()
                        for m in byID.values {
                            manager.membersDictionary[m.name] = m
                        }
                        alertMessage = "Successfully loaded \(count) member(s)."
                    }
                    manager.isDirty = false
                    manager.focusedMemberId = nil
                    showingAlert = true
                }
                
            } catch {
                alertMessage = "Error processing file: \(error.localizedDescription)"
                showingAlert = true
            }
            
        case .failure(let error):
            alertMessage = "Error selecting file: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

