import SwiftUI
import QuickLook

struct AllAttachmentsView: View {
    let folderBookmark: Data
    @Environment(\.dismiss) private var dismiss
    
    @State private var folderURL: URL?
    @State private var attachmentsURL: URL?
    @State private var errorMessage: String?
    @State private var fileURLs: [URL] = []
    @State private var showingPreview: Bool = false
    @State private var previewURL: URL?

    @State private var isAccessing: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                } else if let _ = attachmentsURL {
                    List {
                        ForEach(fileURLs, id: \.self) { fileURL in
                            Button {
                                previewURL = fileURL
                                showingPreview = true
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(fileURL.lastPathComponent)
                                    Text(memberNamePrefix(from: fileURL.lastPathComponent))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: deleteFiles)
                    }
                    .listStyle(.plain)
                    .refreshable {
                        refreshFiles()
                    }
                    .sheet(isPresented: $showingPreview) {
                        if let previewURL, AttachmentPreviewController.isAvailable {
                            AttachmentPreviewController(url: previewURL)
                        } else {
                            Text("Preview is not available for this file.")
                                .padding()
                        }
                    }
                } else {
                    ProgressView("Loading Attachments...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("All Attachments")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        refreshFiles()
                    }
                }
            }
            .onAppear(perform: startAccess)
            .onDisappear(perform: stopAccess)
        }
    }
    
    private func startAccess() {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: folderBookmark, options: [], bookmarkDataIsStale: &isStale)
            if isStale {
                errorMessage = "Bookmark data is stale."
                return
            }
            if url.startAccessingSecurityScopedResource() {
                isAccessing = true
                folderURL = url
                do {
                    attachmentsURL = try AttachmentsStorage.ensureAttachmentsFolder(in: url)
                    refreshFiles()
                } catch {
                    errorMessage = "Failed to create or access Attachments folder: \(error.localizedDescription)"
                }
            } else {
                errorMessage = "Failed to access security scoped resource."
            }
        } catch {
            errorMessage = "Failed to resolve folder bookmark: \(error.localizedDescription)"
        }
    }
    
    private func stopAccess() {
        if isAccessing {
            folderURL?.stopAccessingSecurityScopedResource()
            isAccessing = false
        }
    }
    
    private func refreshFiles() {
        guard let attachmentsURL else {
            fileURLs = []
            return
        }
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: attachmentsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            fileURLs = contents.filter { $0.isFileURL }
        } catch {
            errorMessage = "Failed to list attachments: \(error.localizedDescription)"
            fileURLs = []
        }
    }
    
    private func memberNamePrefix(from fileName: String) -> String {
        // substring before last hyphen if followed by a number
        if let lastHyphenRange = fileName.range(of: "-", options: .backwards) {
            let afterHyphen = fileName.suffix(from: lastHyphenRange.upperBound)
            if !afterHyphen.isEmpty,
               let _ = Int(afterHyphen.prefix { $0.isNumber }) {
                return String(fileName.prefix(upTo: lastHyphenRange.lowerBound))
            }
        }
        // else substring before first dot
        if let dotRange = fileName.firstIndex(of: ".") {
            return String(fileName.prefix(upTo: dotRange))
        }
        return fileName
    }
    
    private func deleteFiles(at offsets: IndexSet) {
        guard let attachmentsURL else { return }
        for index in offsets {
            let fileURL = fileURLs[index]
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                // Could add error handling here
            }
        }
        refreshFiles()
    }
}

private extension AttachmentPreviewController {
    static var isAvailable: Bool {
        return true
    }
}
