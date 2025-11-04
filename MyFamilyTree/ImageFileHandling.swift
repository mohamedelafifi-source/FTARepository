//
//  ImageFileHandling.swift
//  MyFamilyTree
//
//  Created by Mohamed El Afifi on 9/30/25.
//


import SwiftUI
import UniformTypeIdentifiers
import Foundation


// MARK: - Local, unique FileDocument for general exports
struct TempExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .plainText, .json, .png, .jpeg] }
    
    var data: Data
    
    init(data: Data) {
        self.data = data
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let d = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = d
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Simple FileDocument for exporting text
struct TextFile: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    
    init(text: String) { self.text = text }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let s = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = s
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: text.data(using: .utf8)!)
    }
}

// MARK: - Raw data document (for images or arbitrary bytes)
struct DataFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .png, .jpeg, .json, .plainText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let d = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = d
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Export helper using Binding or global flag
struct FileExportManager {
    static func exportText(_ text: String,
                           suggestedName: String = "MyTextFile",
                           isPresented: Binding<Bool>) -> some View {
        EmptyView()
            .fileExporter(
                isPresented: isPresented,
                document: TextFile(text: text),
                contentType: .plainText,
                defaultFilename: suggestedName
            ) { result in
                switch result {
                case .success(let url):
                    print("✅ Saved to", url)
                case .failure(let error):
                    print("❌ Saving failed:", error.localizedDescription)
                }
            }
    }
    
    static func exportData(_ data: Data,
                           contentType: UTType,
                           suggestedName: String = "File",
                           isPresented: Binding<Bool>) -> some View {
        EmptyView()
            .fileExporter(
                isPresented: isPresented,
                document: DataFile(data: data),
                contentType: contentType,
                defaultFilename: suggestedName
            ) { result in
                switch result {
                case .success(let url):
                    print("✅ Saved to", url)
                case .failure(let error):
                    print("❌ Saving failed:", error.localizedDescription)
                }
            }
    }
    
    static func exportTextUsingGlobal(text: String, suggestedName: String = "MyTextFile") -> some View {
        let binding = Binding<Bool>(
            get: { GlobalVariables.shared.showExporter },
            set: { GlobalVariables.shared.showExporter = $0 }
        )
        return exportText(text, suggestedName: suggestedName, isPresented: binding)
    }
}

// MARK: - Simple model & storage manager
struct MyRecord: Codable {
    var id: UUID = .init()
    var title: String
    var timestamp: Date = Date()
}

final class StorageManager {
    static let shared = StorageManager()
    private init() {}
    
    private var baseDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private func jsonURL(named fileName: String) -> URL {
        baseDir.appendingPathComponent(fileName).appendingPathExtension("json")
    }
    
    // Write (overwrite) JSON of any Encodable
    func writeJSON<T: Encodable>(_ value: T, to fileName: String) throws {
        let url = jsonURL(named: fileName)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }
    
    // Read JSON into any Decodable
    func readJSON<T: Decodable>(_ type: T.Type, from fileName: String) throws -> T {
        let url = jsonURL(named: fileName)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    // Append one item to a JSON array file (creating it if missing)
    func appendJSON<T: Codable>(_ element: T, to fileName: String) throws {
        let url = jsonURL(named: fileName)
        var arr: [T] = []
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            if !data.isEmpty {
                arr = try JSONDecoder().decode([T].self, from: data)
            }
        }
        arr.append(element)
        let newData = try JSONEncoder().encode(arr)
        try newData.write(to: url, options: .atomic)
    }
    
    // Images
    private var imagesDir: URL {
        let dir = baseDir.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    /*With @discardableResult:he warning is suppressed. Callers can ignore the return value without noise.
     */
    @discardableResult
    func saveImage(_ image: UIImage, name: String, asJPEG: Bool = true, quality: CGFloat = 0.9) throws -> URL {
        let url = imagesDir.appendingPathComponent(name).appendingPathExtension(asJPEG ? "jpg" : "png")
        let data = asJPEG ? image.jpegData(compressionQuality: quality) : image.pngData()
        guard let data else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
        return url
    }
    func loadImage(name: String) -> UIImage? {
        let jpg = imagesDir.appendingPathComponent(name).appendingPathExtension("jpg")
        let png = imagesDir.appendingPathComponent(name).appendingPathExtension("png")
        if let img = UIImage(contentsOfFile: jpg.path) { return img }
        if let img = UIImage(contentsOfFile: png.path) { return img }
        return nil
    }
    func listImageURLs() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil)) ?? []
    }
}

// MARK: - Pickers
struct FolderPickerView: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        vc.delegate = context.coordinator
        vc.allowsMultipleSelection = false
        return vc
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            onPick(url)
        }
    }
}

struct JSONPickerView: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: false)
        vc.delegate = context.coordinator
        vc.allowsMultipleSelection = false
        return vc
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            onPick(url)
        }
    }
}

// Simple gallery for images saved in app sandbox
struct ImagesListView: View {
    @State private var images: [URL] = []
    var body: some View {
        List(images, id: \.self) { url in
            HStack {
                Image(systemName: "photo")
                Text(url.lastPathComponent)
                    .lineLimit(1)
            }
        }
        .onAppear {
            images = StorageManager.shared.listImageURLs()
        }
        .navigationTitle("Saved Images")
    }
}
/////
// MARK: - Photo Handling for StorageManager
//
// These methods support the image features used by PhotoImportService and PhotoBrowserView:
// - ensurePhotoIndex: make sure photo-index.json exists
// - loadPhotoIndex: read and decode photo index
// - appendToPhotoIndex: add new entry
// - saveImageData: save image bytes with unique name (centralized here)

extension StorageManager {
    /// Create or return the photo index JSON inside the chosen folder.
    /// If the file doesn't exist, writes an empty array `[]`.
    func ensurePhotoIndex(in folder: URL, fileName: String) throws -> URL {
        // Ensure the folder exists
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let url = folder.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            let empty: [PhotoIndexEntry] = []
            let data = try JSONEncoder().encode(empty)
            try data.write(to: url, options: [.atomic])
        }
        return url
    }

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            value = try? container.decode(T.self)
        }
    }

    func loadPhotoIndex(from indexURL: URL) throws -> [PhotoIndexEntry] {
        let data = try Data(contentsOf: indexURL)

        let decoder = JSONDecoder()

        // 1) Try strict decoding first
        if let strict = try? decoder.decode([PhotoIndexEntry].self, from: data) {
            print("[StorageManager] loadPhotoIndex: decoded entries=", strict.count)
            return strict
        }

        // 2) Lossy decode: skip malformed items instead of throwing
        let lossy = try decoder.decode([Lossy<PhotoIndexEntry>].self, from: data)
        let compact = lossy.compactMap { $0.value }
        print("[StorageManager] loadPhotoIndex: decoded entries=", compact.count)
        return compact
    }

    /// Append one entry and re-save the photo index.
    func appendToPhotoIndex(name: String, fileName: String, indexURL: URL) throws {
        var current = (try? loadPhotoIndex(from: indexURL)) ?? []
        current.append(PhotoIndexEntry(name: name, fileName: fileName))
        let data = try JSONEncoder().encode(current)
        try data.write(to: indexURL, options: [.atomic])
    }

    /// Save raw image bytes as <preferredBaseName>-UUID.ext in the folder.
    func saveImageData(
        _ data: Data,
        into folder: URL,
        preferredBaseName: String,
        ext: String
    ) throws -> URL {
        // Ensure the folder exists
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let safeBase = preferredBaseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Person"
            : preferredBaseName
        let filename = "\(safeBase)-\(UUID().uuidString).\(ext)"
        let url = folder.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        return url
    }
}

