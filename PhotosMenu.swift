import SwiftUI
import Foundation

struct PhotosMenu: View {
    @ObservedObject var globals = GlobalVariables.shared
    @ObservedObject var dataManager = FamilyDataManager.shared

    @Binding var showGallery: Bool
    @Binding var showFilteredPhotos: Bool
    @Binding var showPhotoImporter: Bool
    @Binding var showNamePrompt: Bool
    @Binding var tempNameInput: String
    @Binding var filteredNamesForPhotos: [String]

    @Binding var alertMessage: String
    @Binding var showAlert: Bool
    @Binding var showSuccess: Bool
    @Binding var successMessage: String

    @Binding var showResetConfirm: Bool

    @State private var showAllAttachments: Bool = false

    private func resolvedFolderURL() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "selectedFolderBookmark") else { return nil }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            return url
        } catch {
            return nil
        }
    }

    var body: some View {
        Group {
            Button("Browse All Attachments") {
                guard let bookmark = UserDefaults.standard.data(forKey: "selectedFolderBookmark") else {
                    alertMessage = "Select a storage folder first."
                    showAlert = true
                    return
                }
                var isStale = false
                let folder: URL
                do {
                    folder = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                } catch {
                    alertMessage = "Failed to resolve the selected folder."
                    showAlert = true
                    return
                }
                guard folder.startAccessingSecurityScopedResource() else {
                    alertMessage = "Failed to access the selected folder."
                    showAlert = true
                    return
                }
                defer { folder.stopAccessingSecurityScopedResource() }

                do {
                    try AttachmentsStorage.ensureAttachmentsFolder(in: folder)
                } catch {
                    alertMessage = "Failed to ensure attachments folder: \(error.localizedDescription)"
                    showAlert = true
                    return
                }

                showAllAttachments = true
            }
            .disabled(resolvedFolderURL() == nil)
        }
        .font(.footnote)
        .sheet(isPresented: $showAllAttachments) {
            if let bookmark = UserDefaults.standard.data(forKey: "selectedFolderBookmark") {
                AllAttachmentsView(folderBookmark: bookmark)
            } else {
                VStack {
                    Text("Error: No storage folder selected.")
                        .font(.headline)
                        .padding()
                }
                .frame(minWidth: 300, minHeight: 100)
            }
        }
    }
}
