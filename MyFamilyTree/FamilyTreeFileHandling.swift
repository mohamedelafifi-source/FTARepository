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
            print("DEBUG FileHandlingView fileImporter presented, action:", String(describing: importAction), "time:", Date())
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
            print("DEBUG FileHandlingView onAppear, command:", String(describing: command), "time:", Date())
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
                        print("DEBUG FH will try preselectedURL:", url)
                        // Load immediately without showing a picker
                        processImportedFile(.success(url), isAppending: false)
                    } else {
                        print("DEBUG FH no preselectedURL; skipping load")
                        // No preselected URL; do nothing (ContentView should provide it)
                        break
                    }
                }
            }
        }
        .onDisappear {
            print("DEBUG FileHandlingView onDisappear time:", Date())
        }
    }
    
    // MARK: - Helper Functions
    
    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(_):
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
            print("DEBUG FH processing URL:", url)
            
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
                print("DEBUG FH decoded members count:", importedMembers.count)
                print("DEBUG FH starting dictionary update, appending:", isAppending)
                let count = importedMembers.count
                
                DispatchQueue.main.async {
                    if isAppending {
                        for member in importedMembers {
                            if var existingMember = manager.membersDictionary[member.name] {
                                existingMember.parents.append(contentsOf: member.parents.filter { !existingMember.parents.contains($0) })
                                existingMember.spouses.append(contentsOf: member.spouses.filter { !existingMember.spouses.contains($0) })
                                existingMember.children.append(contentsOf: member.children.filter { !existingMember.children.contains($0) })
                                existingMember.siblings.append(contentsOf: member.siblings.filter { !existingMember.siblings.contains($0) })
                                manager.membersDictionary[member.name] = existingMember
                            } else {
                                manager.membersDictionary[member.name] = member
                            }
                        }
                        alertMessage = "Successfully appended \(count) member(s)."
                    } else {
                        manager.membersDictionary.removeAll()
                        for member in importedMembers {
                            manager.membersDictionary[member.name] = member
                        }
                        alertMessage = "Successfully loaded \(count) member(s)."
                    }
                    print("DEBUG FH dictionary update done. Count now:", manager.membersDictionary.count)
                    print("DEBUG FH calling linkFamilyRelations")
                    manager.linkFamilyRelations()
                    print("DEBUG FH linkFamilyRelations done")
                    print("DEBUG FH calling assignLevels")
                    manager.assignLevels()
                    print("DEBUG FH assignLevels done")
                    print("DEBUG FH will show alert:", alertMessage)
                    showingAlert = true
                }
                
            } catch {
                print("DEBUG FH decode error:", error)
                alertMessage = "Error processing file: \(error.localizedDescription)"
                showingAlert = true
            }
            
        case .failure(let error):
            alertMessage = "Error selecting file: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

