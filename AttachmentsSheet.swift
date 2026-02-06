import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct AttachmentsSheet: View {
    let memberName: String
    let folderBookmark: Data
    let onDismiss: () -> Void

    @State private var folderURL: URL?
    @State private var attachments: [URL] = []
    @State private var isPickerPresented = false
    @State private var previewURL: URL?
    @State private var showingPreview = false
    @State private var deleteCandidate: URL?
    @State private var isDeleteConfirmationPresented = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationView {
            Group {
                if folderURL == nil {
                    Text("Loading attachments...")
                        .foregroundColor(.secondary)
                } else {
                    List {
                        ForEach(attachments, id: \.self) { attachment in
                            Button(action: {
                                previewURL = attachment
                                showingPreview = true
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
                    .sheet(isPresented: $showingPreview) {
                        if let previewURL {
                            AttachmentPreviewController(url: previewURL)
                        } else {
                            Text("Preview is not available.")
                                .padding()
                        }
                    }
                }
            }
            .navigationTitle("Attachments for \(memberName)")
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
                case .failure:
                    break
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
                // Could recreate bookmark here if needed, but skipping.
            }
            if url.startAccessingSecurityScopedResource() {
                folderURL = url
                loadAttachments()
            }
        } catch {
            folderURL = nil
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
        let ext = sourceURL.pathExtension
        let destURL = AttachmentsStorage.nextAttachmentURL(for: memberName, originalExtension: ext, in: folderURL)
        do {
            try AttachmentsStorage.savePickedFile(from: sourceURL, to: destURL)
            let attrs = try FileManager.default.attributesOfItem(atPath: destURL.path)
            if let size = attrs[.size] as? NSNumber, size.intValue > 0 {
                refreshList()
            } else {
                try? FileManager.default.removeItem(at: destURL)
                alertMessage = "Failed to save attachment (empty file)."
                showAlert = true
            }
        } catch {
            // Ignore errors silently
        }
    }

    private func deleteAttachments(at offsets: IndexSet) {
        guard let folderURL = folderURL else { return }
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
            // ignore errors silently
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
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        // Nothing to update
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
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
