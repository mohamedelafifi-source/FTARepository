//Adding and displaying the attachments linked to a member
//---------------------------------------------------------
import SwiftUI
import UniformTypeIdentifiers
import QuickLook

// MARK: - Preview Item Wrapper
struct PreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct AttachmentsSheet: View {
    let memberName: String
    let folderBookmark: Data
    let onDismiss: () -> Void

    @State private var folderURL: URL?
    @State private var attachments: [URL] = []
    @State private var isPickerPresented = false
    @State private var previewItem: PreviewItem?
    @State private var deleteCandidate: URL?
    @State private var isDeleteConfirmationPresented = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        let _ = print("DEBUG: AttachmentsSheet created with memberName: '\(memberName)'")
        
        NavigationView {
            Group {
                if memberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        Text("No Member Selected")
                            .font(.headline)
                        Text("Please close this sheet and try selecting a member again.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if folderURL == nil {
                    VStack(spacing: 20) {
                        ProgressView()
                        Text("Loading attachments...")
                            .foregroundColor(.secondary)
                    }
                } else if attachments.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No attachments yet")
                            .font(.headline)
                        Text("Tap the + button to add photos or PDFs")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(attachments, id: \.self) { attachment in
                            Button(action: {
                                // Verify file exists before attempting preview
                                guard FileManager.default.fileExists(atPath: attachment.path) else {
                                    errorMessage = "File not found: \(attachment.lastPathComponent)"
                                    showError = true
                                    return
                                }
                                
                                // Set the preview item - this will trigger the sheet
                                previewItem = PreviewItem(url: attachment)
                            }) {
                                HStack {
                                    Image(systemName: iconName(for: attachment))
                                        .foregroundColor(.accentColor)
                                    Text(attachment.lastPathComponent)
                                        .lineLimit(1)
                                    Spacer()
                                    Button(role: .destructive) {
                                        deleteCandidate = attachment
                                        isDeleteConfirmationPresented = true
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                            }
                        }
                        .onDelete(perform: deleteAttachments)
                    }
                    .confirmationDialog(
                        "Are you sure you want to delete \"\(deleteCandidate?.lastPathComponent ?? "")\"?",
                        isPresented: $isDeleteConfirmationPresented,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            if let candidate = deleteCandidate {
                                delete(attachment: candidate)
                                refreshList()
                            }
                        }
                        Button("Cancel", role: .cancel) {
                            deleteCandidate = nil
                        }
                    }
                    .sheet(item: $previewItem) { item in
                        AttachmentPreviewController(url: item.url)
                    }
                }
            }
            .navigationTitle(memberName.isEmpty ? "Attachments" : "Attachments for \(memberName)")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if memberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            alertMessage = "Please select a member before adding an attachment."
                            showAlert = true
                            return
                        }
                        isPickerPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Attachment")
                }
            }
            .fileImporter(
                isPresented: $isPickerPresented,
                allowedContentTypes: [UTType.image, UTType.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let pickedURL = urls.first,
                          let folderURL = folderURL else { return }
                    if memberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        alertMessage = "Please select a member before adding an attachment."
                        showAlert = true
                        return
                    }
                    savePickedFile(from: pickedURL, toFolder: folderURL)
                case .failure(let error):
                    errorMessage = "Failed to import file: \(error.localizedDescription)"
                    showError = true
                }
            }
            .onAppear {
                resolveBookmark()
            }
            .onDisappear {
                stopAccessing()
            }
            .alert("Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func iconName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "gif", "tiff", "bmp", "webp"].contains(ext) {
            return "photo"
        }
        if ext == "pdf" {
            return "doc.richtext"
        }
        return "doc"
    }

    private func resolveBookmark() {
        guard folderURL == nil else { return }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: folderBookmark, options: [], bookmarkDataIsStale: &isStale)
            if isStale {
                // Could recreate bookmark here if needed
                print("Warning: Bookmark is stale")
            }
            if url.startAccessingSecurityScopedResource() {
                folderURL = url
                loadAttachments()
            } else {
                errorMessage = "Failed to access the storage folder. Please reselect it in Settings."
                showError = true
            }
        } catch {
            errorMessage = "Failed to access storage folder: \(error.localizedDescription)"
            showError = true
        }
    }

    private func stopAccessing() {
        folderURL?.stopAccessingSecurityScopedResource()
        folderURL = nil
    }

    private func loadAttachments() {
        guard let folderURL = folderURL else { return }
        attachments = AttachmentsStorage.listAttachments(for: memberName, in: folderURL)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func refreshList() {
        loadAttachments()
    }

    private func savePickedFile(from sourceURL: URL, toFolder folderURL: URL) {
        // Start accessing the security-scoped resource
        guard sourceURL.startAccessingSecurityScopedResource() else {
            errorMessage = "Failed to access the selected file."
            showError = true
            return
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }
        
        let ext = sourceURL.pathExtension
        let destURL = AttachmentsStorage.nextAttachmentURL(for: memberName, originalExtension: ext, in: folderURL)
        
        do {
            try AttachmentsStorage.savePickedFile(from: sourceURL, to: destURL)
            
            // Verify the file was saved correctly
            let attrs = try FileManager.default.attributesOfItem(atPath: destURL.path)
            if let size = attrs[.size] as? NSNumber, size.intValue > 0 {
                refreshList()
            } else {
                // Empty file, remove it
                try? FileManager.default.removeItem(at: destURL)
                errorMessage = "Failed to save attachment (empty file)."
                showError = true
            }
        } catch {
            errorMessage = "Failed to save attachment: \(error.localizedDescription)"
            showError = true
        }
    }

    private func deleteAttachments(at offsets: IndexSet) {
        let urlsToDelete = offsets.compactMap { attachments[safe: $0] }
        for url in urlsToDelete {
            delete(attachment: url)
        }
        refreshList()
    }

    private func delete(attachment url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            errorMessage = "Failed to delete attachment: \(error.localizedDescription)"
            showError = true
        }
        refreshList()
        deleteCandidate = nil
    }
}

private extension Collection {
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

struct AttachmentPreviewController: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        // Refresh the preview if needed
        uiViewController.reloadData()
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let parent: AttachmentPreviewController

        init(_ parent: AttachmentPreviewController) {
            self.parent = parent
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            parent.url as QLPreviewItem
        }
    }
}

